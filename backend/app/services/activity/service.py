from dataclasses import asdict
from datetime import date, datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.date_ranges import utc_now
from app.core.exceptions import ConflictError, ValidationError
from app.core.timeparse import parse_supabase_datetime
from app.repositories.activity import ActivityRepository
from app.repositories.calls import CallRepository
from app.services.activity.calc import ActivityTotals, CallSpan, compute_activity

# The app sends a heartbeat about once a minute while its process is alive
# (foreground OR background). If the last one is older than this, the app
# was closed or killed in between: the old session ends at its last
# heartbeat and a new one starts now, so time the app was NOT reporting is
# never counted as logged in.
SESSION_TIMEOUT = timedelta(minutes=3)

# Today's stored rollup row is at most this stale after a heartbeat. (Sign
# out and starting/ending a break always refresh it immediately.)
ROLLUP_REFRESH = timedelta(minutes=5)


def _iso(value: datetime) -> str:
    return value.isoformat()


class ActivityService:
    """Login Analytics: how long a member had the app signed in, their
    breaks, and (combined with their calls) talk / wrap-up / idle time.

    Raw facts are stored (`agent_sessions`, `agent_breaks`, plus the
    existing `calls`); the totals are always *computed* from them
    (`compute_activity`) and the per-day results stored in
    `agent_daily_activity` for the admin panel to read. Everything here is
    the caller's own data: the write path is RLS-restricted to
    `current_member_id`, and the only cross-member read (daily rows for a
    manager) is RLS too."""

    def __init__(
        self,
        client: Client,
        *,
        repository: ActivityRepository | None = None,
        calls: CallRepository | None = None,
    ):
        self._client = client
        self._repo = repository or ActivityRepository(client)
        self._calls = calls or CallRepository(client)

    # ---- the app reporting in ----

    def heartbeat(self, workspace_id: UUID, *, utc_offset_minutes: int = 0, now: datetime | None = None) -> dict[str, Any]:
        """Called about once a minute by the running app. Starts a session
        if there is none (or the last one timed out), otherwise extends it,
        and keeps today's stored rollup reasonably fresh."""
        now = now or utc_now()
        member_id = self._current_member_id(workspace_id)
        self._ensure_session(workspace_id, member_id, now)
        self._refresh_daily(workspace_id, member_id, utc_offset_minutes, now, force=False)
        return self._status(workspace_id, member_id)

    def sign_out(self, workspace_id: UUID, *, utc_offset_minutes: int = 0, now: datetime | None = None) -> dict[str, Any]:
        """Ends the session (and any open break) right now and writes the
        final rollup, instead of waiting for the heartbeats to lapse."""
        now = now or utc_now()
        member_id = self._current_member_id(workspace_id)
        session = self._repo.get_open_session(workspace_id, member_id)
        if session is not None:
            started = parse_supabase_datetime(session["started_at"])
            self._end_session(workspace_id, member_id, session, ended_at=max(now, started))
        self._refresh_daily(workspace_id, member_id, utc_offset_minutes, now, force=True)
        return {"on_break": False, "break_started_at": None}

    def start_break(self, workspace_id: UUID, *, utc_offset_minutes: int = 0, now: datetime | None = None) -> dict[str, Any]:
        now = now or utc_now()
        member_id = self._current_member_id(workspace_id)
        self._ensure_session(workspace_id, member_id, now)
        if self._repo.get_open_break(workspace_id, member_id) is None:
            try:
                self._repo.open_break(workspace_id, member_id, _iso(now))
            except ConflictError:
                pass  # raced with another request that already started it
        self._refresh_daily(workspace_id, member_id, utc_offset_minutes, now, force=True)
        return self._status(workspace_id, member_id)

    def end_break(self, workspace_id: UUID, *, utc_offset_minutes: int = 0, now: datetime | None = None) -> dict[str, Any]:
        now = now or utc_now()
        member_id = self._current_member_id(workspace_id)
        current = self._repo.get_open_break(workspace_id, member_id)
        if current is not None:
            started = parse_supabase_datetime(current["started_at"])
            self._repo.close_break(current["id"], _iso(max(now, started)))
        self._refresh_daily(workspace_id, member_id, utc_offset_minutes, now, force=True)
        return self._status(workspace_id, member_id)

    # ---- reading ----

    def get_summary(
        self, workspace_id: UUID, *, since: datetime, until: datetime, now: datetime | None = None
    ) -> dict[str, Any]:
        """The caller's own totals for [since, until), computed fresh from
        the raw rows (so it includes the session in progress), plus whether
        they are on a break right now."""
        if since >= until:
            raise ValidationError("'since' must be before 'until'.")
        now = now or utc_now()
        member_id = self._current_member_id(workspace_id)
        totals = self._totals(workspace_id, member_id, since, until, now)
        return {"since": since, "until": until, **asdict(totals), **self._status(workspace_id, member_id)}

    def list_daily(
        self, workspace_id: UUID, *, since_day: date, until_day: date, member_id: str | None = None
    ) -> list[dict[str, Any]]:
        """Stored per-day rows. Whose rows come back is RLS: a member gets
        only their own, manager-or-above everyone's."""
        if since_day > until_day:
            raise ValidationError("'since' must not be after 'until'.")
        return self._repo.list_daily(workspace_id, since_day, until_day, member_id)

    # ---- sessions ----

    def _ensure_session(self, workspace_id: UUID, member_id: str, now: datetime) -> None:
        session = self._repo.get_open_session(workspace_id, member_id)
        if session is not None:
            last_seen = parse_supabase_datetime(session["last_seen_at"])
            if now - last_seen > SESSION_TIMEOUT:
                # Heartbeats stopped: it ended when we last heard from it.
                self._end_session(workspace_id, member_id, session, ended_at=last_seen)
                session = None
        if session is not None:
            self._repo.touch_session(session["id"], _iso(now))
            return
        try:
            self._repo.open_session(workspace_id, member_id, _iso(now))
        except ConflictError:
            # Another request opened one between our read and insert.
            current = self._repo.get_open_session(workspace_id, member_id)
            if current is not None:
                self._repo.touch_session(current["id"], _iso(now))

    def _end_session(self, workspace_id: UUID, member_id: str, session: dict[str, Any], *, ended_at: datetime) -> None:
        self._repo.close_session(session["id"], _iso(ended_at))
        # A break cannot outlive the session it happened in.
        open_break = self._repo.get_open_break(workspace_id, member_id)
        if open_break is not None:
            started = parse_supabase_datetime(open_break["started_at"])
            self._repo.close_break(open_break["id"], _iso(max(ended_at, started)))

    def _status(self, workspace_id: UUID, member_id: str) -> dict[str, Any]:
        open_break = self._repo.get_open_break(workspace_id, member_id)
        return {
            "on_break": open_break is not None,
            "break_started_at": parse_supabase_datetime(open_break["started_at"]) if open_break else None,
        }

    # ---- the maths, fed from the database ----

    def _totals(self, workspace_id: UUID, member_id: str, since: datetime, until: datetime, now: datetime) -> ActivityTotals:
        since_iso, until_iso = _iso(since), _iso(until)
        sessions = [
            (
                parse_supabase_datetime(row["started_at"]),
                parse_supabase_datetime(row["ended_at"] or row["last_seen_at"]),
            )
            for row in self._repo.list_sessions(workspace_id, member_id, since_iso, until_iso)
        ]
        breaks = [
            (
                parse_supabase_datetime(row["started_at"]),
                parse_supabase_datetime(row["ended_at"]) if row.get("ended_at") else now,
            )
            for row in self._repo.list_breaks(workspace_id, member_id, since_iso, until_iso)
        ]
        calls = [
            CallSpan(
                started_at=parse_supabase_datetime(row["started_at"]),
                connected_at=parse_supabase_datetime(row["connected_at"]) if row.get("connected_at") else None,
                ended_at=parse_supabase_datetime(row["ended_at"]) if row.get("ended_at") else None,
            )
            for row in self._calls.list_for_activity(workspace_id, agent_member_id=member_id, since=since_iso, until=until_iso)
        ]
        return compute_activity(since=since, until=until, now=now, sessions=sessions, breaks=breaks, calls=calls)

    # ---- the stored daily rollup ----

    def _refresh_daily(self, workspace_id: UUID, member_id: str, utc_offset_minutes: int, now: datetime, *, force: bool) -> None:
        """Recompute and store the member's row for their local "today".

        On a heartbeat this is throttled (at most every ROLLUP_REFRESH); the
        first write of a new local day also closes out yesterday, so the
        last row of the previous day is never left ~5 minutes short.
        `force` (sign-out, break start/end) always writes."""
        local_day = (now + timedelta(minutes=utc_offset_minutes)).date()
        first_of_day = False
        if not force:
            existing = self._repo.get_daily(workspace_id, member_id, local_day)
            if existing is not None and now - parse_supabase_datetime(existing["updated_at"]) < ROLLUP_REFRESH:
                return
            first_of_day = existing is None
        self._write_daily(workspace_id, member_id, local_day, utc_offset_minutes, now, skip_if_empty=False)
        if first_of_day:
            self._write_daily(workspace_id, member_id, local_day - timedelta(days=1), utc_offset_minutes, now, skip_if_empty=True)

    def _write_daily(
        self, workspace_id: UUID, member_id: str, day: date, utc_offset_minutes: int, now: datetime, *, skip_if_empty: bool
    ) -> None:
        offset = timedelta(minutes=utc_offset_minutes)
        # The instant that local midnight falls on, in UTC.
        start = datetime(day.year, day.month, day.day, tzinfo=timezone.utc) - offset
        totals = self._totals(workspace_id, member_id, start, start + timedelta(days=1), now)
        if skip_if_empty and not any(asdict(totals).values()):
            return
        self._repo.upsert_daily(workspace_id, member_id, day, {"utc_offset_minutes": utc_offset_minutes, **asdict(totals)})

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        if not result.data:
            raise ValidationError("Could not resolve your workspace membership.")
        return result.data
