from datetime import date
from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError
from app.repositories.base import BaseRepository

_UNIQUE_VIOLATION = "23505"


class ActivityRepository(BaseRepository):
    """`agent_sessions`, `agent_breaks` and `agent_daily_activity`
    (supabase/migrations/000031_agent_activity.sql). One repository for the
    three because they are only ever used together — a heartbeat touches a
    session, may close a break, and refreshes the day's rollup.

    Always runs on the request's own user-scoped client, so RLS is what
    stops a member writing anyone else's rows (`member_id =
    current_member_id(...)`); manager-or-above reading every member's
    rows is also RLS, not code here. Nothing is ever deleted."""

    table_name = "agent_sessions"

    # ---- sessions ----

    def get_open_session(self, workspace_id: UUID, member_id: str) -> dict[str, Any] | None:
        rows = (
            self._client.table("agent_sessions")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("member_id", member_id)
            .is_("ended_at", "null")
            .limit(1)
            .execute()
            .data
        )
        return rows[0] if rows else None

    def open_session(self, workspace_id: UUID, member_id: str, at_iso: str) -> dict[str, Any]:
        """Starts a session. Raises ConflictError if the member already has
        an open one (the partial unique index) — two devices, or a retry
        racing itself; the caller re-reads and carries on with that one."""
        row = {
            "workspace_id": str(workspace_id),
            "member_id": member_id,
            "started_at": at_iso,
            "last_seen_at": at_iso,
        }
        return self._insert("agent_sessions", row)

    def touch_session(self, session_id: str, at_iso: str) -> None:
        self._client.table("agent_sessions").update({"last_seen_at": at_iso}).eq("id", session_id).execute()

    def close_session(self, session_id: str, ended_at_iso: str) -> None:
        self._client.table("agent_sessions").update({"ended_at": ended_at_iso}).eq("id", session_id).execute()

    def list_sessions(self, workspace_id: UUID, member_id: str, since_iso: str, until_iso: str) -> list[dict[str, Any]]:
        """Sessions that overlap [since, until): they began before `until`
        and either have ended at/after `since` or are still open (an open
        one's effective end is decided by the caller — its last_seen_at)."""
        return (
            self._client.table("agent_sessions")
            .select("started_at,last_seen_at,ended_at")
            .eq("workspace_id", str(workspace_id))
            .eq("member_id", member_id)
            .lt("started_at", until_iso)
            .or_(f"ended_at.gte.{since_iso},ended_at.is.null")
            .order("started_at")
            .execute()
            .data
            or []
        )

    # ---- breaks ----

    def get_open_break(self, workspace_id: UUID, member_id: str) -> dict[str, Any] | None:
        rows = (
            self._client.table("agent_breaks")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("member_id", member_id)
            .is_("ended_at", "null")
            .limit(1)
            .execute()
            .data
        )
        return rows[0] if rows else None

    def open_break(self, workspace_id: UUID, member_id: str, at_iso: str) -> dict[str, Any]:
        row = {"workspace_id": str(workspace_id), "member_id": member_id, "started_at": at_iso}
        return self._insert("agent_breaks", row)

    def close_break(self, break_id: str, ended_at_iso: str) -> None:
        self._client.table("agent_breaks").update({"ended_at": ended_at_iso}).eq("id", break_id).execute()

    def list_breaks(self, workspace_id: UUID, member_id: str, since_iso: str, until_iso: str) -> list[dict[str, Any]]:
        return (
            self._client.table("agent_breaks")
            .select("started_at,ended_at")
            .eq("workspace_id", str(workspace_id))
            .eq("member_id", member_id)
            .lt("started_at", until_iso)
            .or_(f"ended_at.gte.{since_iso},ended_at.is.null")
            .order("started_at")
            .execute()
            .data
            or []
        )

    # ---- daily rollup ----

    def get_daily(self, workspace_id: UUID, member_id: str, day: date) -> dict[str, Any] | None:
        rows = (
            self._client.table("agent_daily_activity")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("member_id", member_id)
            .eq("day", day.isoformat())
            .limit(1)
            .execute()
            .data
        )
        return rows[0] if rows else None

    def upsert_daily(self, workspace_id: UUID, member_id: str, day: date, values: dict[str, Any]) -> None:
        row = {"workspace_id": str(workspace_id), "member_id": member_id, "day": day.isoformat(), **values}
        self._client.table("agent_daily_activity").upsert(row, on_conflict="workspace_id,member_id,day").execute()

    def list_daily(
        self, workspace_id: UUID, since_day: date, until_day: date, member_id: str | None = None
    ) -> list[dict[str, Any]]:
        """Stored per-day rows for [since_day, until_day] inclusive. RLS
        decides whose rows come back: a member only ever gets their own,
        manager-or-above get everyone's (optionally narrowed to one)."""
        query = (
            self._client.table("agent_daily_activity")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .gte("day", since_day.isoformat())
            .lte("day", until_day.isoformat())
        )
        if member_id is not None:
            query = query.eq("member_id", member_id)
        return query.order("day", desc=True).order("member_id").execute().data or []

    # ---- helpers ----

    def _insert(self, table: str, row: dict[str, Any]) -> dict[str, Any]:
        try:
            response = self._client.table(table).insert(row).execute()
        except APIError as exc:
            if exc.code == _UNIQUE_VIOLATION:
                raise ConflictError("Already open.") from exc
            raise
        return response.data[0] if response.data else row
