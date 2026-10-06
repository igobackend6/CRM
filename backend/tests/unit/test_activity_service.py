from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.core.exceptions import ConflictError, ValidationError
from app.core.timeparse import parse_supabase_datetime
from app.services.activity.service import ROLLUP_REFRESH, SESSION_TIMEOUT, ActivityService
from tests.support.fake_supabase import FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
T0 = datetime(2026, 9, 24, 9, 0, tzinfo=timezone.utc)


def at(minutes: float) -> datetime:
    return T0 + timedelta(minutes=minutes)


class FakeActivityRepository:
    """The repository's contract, in memory — enough to run the service's
    real lifecycle logic (which rows are open, closed, touched)."""

    def __init__(self):
        self.sessions: list[dict] = []
        self.breaks: list[dict] = []
        self.daily: dict[date, dict] = {}
        self.daily_writes: list[tuple[date, dict]] = []
        self._next_id = 0
        # Simulates another request winning the race to open a session.
        self.rival_session_on_next_open = False

    def _id(self) -> str:
        self._next_id += 1
        return f"row-{self._next_id}"

    def get_open_session(self, workspace_id, member_id):
        return next((s for s in self.sessions if s["ended_at"] is None), None)

    def open_session(self, workspace_id, member_id, at_iso):
        if self.rival_session_on_next_open:
            self.rival_session_on_next_open = False
            self.sessions.append({"id": self._id(), "started_at": at_iso, "last_seen_at": at_iso, "ended_at": None})
            raise ConflictError("Already open.")
        row = {"id": self._id(), "started_at": at_iso, "last_seen_at": at_iso, "ended_at": None}
        self.sessions.append(row)
        return row

    def touch_session(self, session_id, at_iso):
        next(s for s in self.sessions if s["id"] == session_id)["last_seen_at"] = at_iso

    def close_session(self, session_id, ended_at_iso):
        next(s for s in self.sessions if s["id"] == session_id)["ended_at"] = ended_at_iso

    def list_sessions(self, workspace_id, member_id, since_iso, until_iso):
        return list(self.sessions)

    def get_open_break(self, workspace_id, member_id):
        return next((b for b in self.breaks if b["ended_at"] is None), None)

    def open_break(self, workspace_id, member_id, at_iso):
        row = {"id": self._id(), "started_at": at_iso, "ended_at": None}
        self.breaks.append(row)
        return row

    def close_break(self, break_id, ended_at_iso):
        next(b for b in self.breaks if b["id"] == break_id)["ended_at"] = ended_at_iso

    def list_breaks(self, workspace_id, member_id, since_iso, until_iso):
        return list(self.breaks)

    def get_daily(self, workspace_id, member_id, day):
        return self.daily.get(day)

    def upsert_daily(self, workspace_id, member_id, day, values):
        self.daily_writes.append((day, values))
        self.daily[day] = {**values, "updated_at": self.now_iso}

    def list_daily(self, workspace_id, since_day, until_day, member_id=None):
        return [{"day": d, **row} for d, row in self.daily.items() if since_day <= d <= until_day]

    # The service stamps `updated_at` via the DB trigger; the fake stamps it
    # with whatever the test says "now" is.
    now_iso = at(0).isoformat()


class FakeCalls:
    def __init__(self, rows=()):
        self.rows = list(rows)

    def list_for_activity(self, workspace_id, *, agent_member_id, since, until):
        return list(self.rows)


def make(calls=(), *, repo=None):
    repo = repo or FakeActivityRepository()
    client = FakeSupabaseClient(rpc_responses={"current_member_id": MEMBER_ID})
    return ActivityService(client, repository=repo, calls=FakeCalls(calls)), repo


def call_row(start_min: float, connect_min: float | None, end_min: float | None) -> dict:
    return {
        "started_at": at(start_min).isoformat(),
        "connected_at": at(connect_min).isoformat() if connect_min is not None else None,
        "ended_at": at(end_min).isoformat() if end_min is not None else None,
    }


def heartbeat(service, repo, minute: float, **kwargs):
    repo.now_iso = at(minute).isoformat()
    return service.heartbeat(WORKSPACE_ID, now=at(minute), **kwargs)


def beat(service, repo, first_minute: int, last_minute: int):
    """A heartbeat every minute, as the real app sends: an app that is
    alive never goes quiet for longer than the session timeout."""
    for minute in range(first_minute, last_minute + 1):
        heartbeat(service, repo, minute)


# ---------------------------------------------------------------------
# sessions
# ---------------------------------------------------------------------


class TestHeartbeatSessions:
    def test_the_first_heartbeat_opens_a_session(self):
        service, repo = make()

        heartbeat(service, repo, 0)

        assert len(repo.sessions) == 1
        assert repo.sessions[0]["started_at"] == at(0).isoformat()
        assert repo.sessions[0]["last_seen_at"] == at(0).isoformat()
        assert repo.sessions[0]["ended_at"] is None

    def test_later_heartbeats_extend_the_same_session(self):
        service, repo = make()

        heartbeat(service, repo, 0)
        heartbeat(service, repo, 1)
        heartbeat(service, repo, 2)

        assert len(repo.sessions) == 1
        assert repo.sessions[0]["started_at"] == at(0).isoformat()
        assert repo.sessions[0]["last_seen_at"] == at(2).isoformat()

    def test_a_heartbeat_just_inside_the_timeout_still_extends_it(self):
        service, repo = make()
        heartbeat(service, repo, 0)

        heartbeat(service, repo, SESSION_TIMEOUT.total_seconds() / 60)  # exactly at the limit

        assert len(repo.sessions) == 1

    def test_a_heartbeat_after_the_timeout_ends_the_old_session_where_it_was_last_heard_and_starts_a_new_one(self):
        """The app was closed or killed for a while. The gap is not login."""
        service, repo = make()
        heartbeat(service, repo, 0)
        heartbeat(service, repo, 2)

        heartbeat(service, repo, 60)

        assert len(repo.sessions) == 2
        old, new = repo.sessions
        assert old["ended_at"] == at(2).isoformat(), "ended at its last heartbeat, not at minute 60"
        assert new["started_at"] == at(60).isoformat()
        assert new["ended_at"] is None

    def test_a_timeout_also_closes_a_break_left_open(self):
        service, repo = make()
        heartbeat(service, repo, 0)
        repo.now_iso = at(1).isoformat()
        service.start_break(WORKSPACE_ID, now=at(1))
        heartbeat(service, repo, 2)

        heartbeat(service, repo, 90)

        assert repo.breaks[0]["ended_at"] == at(2).isoformat()

    def test_losing_the_race_to_open_a_session_touches_the_winner_instead_of_erroring(self):
        service, repo = make()
        repo.rival_session_on_next_open = True

        heartbeat(service, repo, 5)

        assert len(repo.sessions) == 1
        assert repo.sessions[0]["last_seen_at"] == at(5).isoformat()

    def test_a_member_with_no_resolvable_membership_is_rejected(self):
        client = FakeSupabaseClient(rpc_responses={"current_member_id": None})
        service = ActivityService(client, repository=FakeActivityRepository(), calls=FakeCalls())

        with pytest.raises(ValidationError):
            service.heartbeat(WORKSPACE_ID, now=at(0))


class TestSignOut:
    def test_closes_the_session_now(self):
        service, repo = make()
        heartbeat(service, repo, 0)
        heartbeat(service, repo, 1)

        result = service.sign_out(WORKSPACE_ID, now=at(30))

        assert repo.sessions[0]["ended_at"] == at(30).isoformat()
        assert result == {"on_break": False, "break_started_at": None}

    def test_closes_an_open_break_at_the_same_moment(self):
        service, repo = make()
        heartbeat(service, repo, 0)
        service.start_break(WORKSPACE_ID, now=at(10))

        service.sign_out(WORKSPACE_ID, now=at(25))

        assert repo.breaks[0]["ended_at"] == at(25).isoformat()

    def test_with_no_session_is_harmless_and_still_writes_a_rollup(self):
        service, repo = make()

        service.sign_out(WORKSPACE_ID, now=at(30))

        assert repo.sessions == []
        assert len(repo.daily_writes) == 1

    def test_writes_the_final_rollup_immediately_regardless_of_throttling(self):
        service, repo = make()
        heartbeat(service, repo, 0)
        writes_after_heartbeat = len(repo.daily_writes)

        service.sign_out(WORKSPACE_ID, now=at(1))

        assert len(repo.daily_writes) == writes_after_heartbeat + 1

    def test_the_session_never_ends_before_it_started(self):
        """Clock skew: the device clock is behind the server's."""
        service, repo = make()
        heartbeat(service, repo, 10)

        service.sign_out(WORKSPACE_ID, now=at(5))  # earlier than started_at

        assert repo.sessions[0]["ended_at"] == at(10).isoformat()


# ---------------------------------------------------------------------
# breaks
# ---------------------------------------------------------------------


class TestBreaks:
    def test_starting_a_break_opens_a_session_if_there_is_none(self):
        service, repo = make()

        result = service.start_break(WORKSPACE_ID, now=at(0))

        assert len(repo.sessions) == 1
        assert len(repo.breaks) == 1
        assert result["on_break"] is True
        assert result["break_started_at"] == at(0)

    def test_starting_a_break_twice_keeps_one_break_and_the_original_start(self):
        service, repo = make()
        service.start_break(WORKSPACE_ID, now=at(0))
        beat(service, repo, 1, 4)

        result = service.start_break(WORKSPACE_ID, now=at(5))

        assert len(repo.breaks) == 1
        assert result["break_started_at"] == at(0)

    def test_ending_a_break_closes_it(self):
        service, repo = make()
        service.start_break(WORKSPACE_ID, now=at(0))

        result = service.end_break(WORKSPACE_ID, now=at(12))

        assert repo.breaks[0]["ended_at"] == at(12).isoformat()
        assert result == {"on_break": False, "break_started_at": None}

    def test_ending_when_not_on_a_break_does_nothing(self):
        service, repo = make()
        heartbeat(service, repo, 0)

        result = service.end_break(WORKSPACE_ID, now=at(5))

        assert repo.breaks == []
        assert result["on_break"] is False

    def test_a_break_never_ends_before_it_started(self):
        service, repo = make()
        service.start_break(WORKSPACE_ID, now=at(10))

        service.end_break(WORKSPACE_ID, now=at(3))  # device clock behind

        assert repo.breaks[0]["ended_at"] == at(10).isoformat()

    def test_a_new_break_can_start_after_the_previous_one_ended(self):
        service, repo = make()
        service.start_break(WORKSPACE_ID, now=at(0))
        service.end_break(WORKSPACE_ID, now=at(5))

        service.start_break(WORKSPACE_ID, now=at(20))

        assert len(repo.breaks) == 2
        assert repo.breaks[1]["ended_at"] is None

    def test_the_heartbeat_reports_the_break_state(self):
        service, repo = make()
        service.start_break(WORKSPACE_ID, now=at(0))

        status = heartbeat(service, repo, 1)

        assert status["on_break"] is True


# ---------------------------------------------------------------------
# the summary (the maths, fed from stored rows)
# ---------------------------------------------------------------------


class TestSummary:
    def _seed(self, service, repo):
        beat(service, repo, 0, 60)  # a 60-minute session so far

    def test_login_is_the_span_of_the_session(self):
        service, repo = make()
        self._seed(service, repo)

        result = service.get_summary(WORKSPACE_ID, since=at(-30), until=at(600), now=at(120))

        assert result["login_seconds"] == 60 * 60

    def test_idle_is_login_minus_everything_else(self):
        service, repo = make(calls=[call_row(10, 11, 21)])
        self._seed(service, repo)
        repo.breaks.append({"id": "b", "started_at": at(30).isoformat(), "ended_at": at(40).isoformat()})

        result = service.get_summary(WORKSPACE_ID, since=at(-30), until=at(600), now=at(120))

        assert result["talk_seconds"] == 10 * 60
        assert result["break_seconds"] == 10 * 60
        assert result["wrap_up_seconds"] == 120
        # login 60m - call 11m (1 ringing + 10 talk) - wrap-up 2m - break 10m.
        assert result["idle_seconds"] == (60 - 11 - 2 - 10) * 60

    def test_the_session_in_progress_is_included(self):
        service, repo = make()
        beat(service, repo, 0, 5)  # still open

        result = service.get_summary(WORKSPACE_ID, since=at(-30), until=at(600), now=at(6))

        assert result["login_seconds"] == 5 * 60

    def test_an_open_break_runs_to_now_and_is_reported(self):
        service, repo = make()
        beat(service, repo, 0, 9)
        service.start_break(WORKSPACE_ID, now=at(10))
        beat(service, repo, 11, 20)

        result = service.get_summary(WORKSPACE_ID, since=at(-30), until=at(600), now=at(20))

        assert result["on_break"] is True
        assert result["break_started_at"] == at(10)
        assert result["break_seconds"] == 10 * 60

    def test_echoes_the_window(self):
        service, repo = make()

        result = service.get_summary(WORKSPACE_ID, since=at(0), until=at(60), now=at(30))

        assert (result["since"], result["until"]) == (at(0), at(60))

    def test_rejects_a_reversed_or_empty_window(self):
        service, _ = make()

        for since, until in [(at(60), at(0)), (at(10), at(10))]:
            with pytest.raises(ValidationError):
                service.get_summary(WORKSPACE_ID, since=since, until=until, now=at(30))

    def test_a_call_row_with_no_times_set_does_not_crash(self):
        service, repo = make(calls=[call_row(10, None, None)])
        self._seed(service, repo)

        result = service.get_summary(WORKSPACE_ID, since=at(-30), until=at(600), now=at(120))

        assert result["talk_seconds"] == 0


# ---------------------------------------------------------------------
# the stored daily rollup
# ---------------------------------------------------------------------


class TestDailyRollup:
    def test_a_heartbeat_stores_todays_row_for_the_local_day(self):
        service, repo = make()

        heartbeat(service, repo, 0)

        day, values = repo.daily_writes[0]
        assert day == date(2026, 9, 24)
        assert values["utc_offset_minutes"] == 0
        assert set(values) == {
            "utc_offset_minutes", "login_seconds", "talk_seconds", "wrap_up_seconds", "break_seconds", "idle_seconds",
        }

    def test_the_local_day_follows_the_utc_offset(self):
        """20:00 UTC on the 24th is already the 25th in India (UTC+5:30)."""
        service, repo = make()
        repo.now_iso = datetime(2026, 9, 24, 20, 0, tzinfo=timezone.utc).isoformat()

        service.heartbeat(WORKSPACE_ID, utc_offset_minutes=330, now=datetime(2026, 9, 24, 20, 0, tzinfo=timezone.utc))

        assert repo.daily_writes[0][0] == date(2026, 9, 25)
        assert repo.daily_writes[0][1]["utc_offset_minutes"] == 330

    def test_the_day_window_starts_at_local_midnight(self):
        """A session from 18:40Z to 19:40Z is 00:10-01:10 on the 25th in IST: all of it is on the 25th."""
        service, repo = make()
        repo.sessions.append(
            {
                "id": "s",
                "started_at": datetime(2026, 9, 24, 18, 40, tzinfo=timezone.utc).isoformat(),
                "last_seen_at": datetime(2026, 9, 24, 19, 40, tzinfo=timezone.utc).isoformat(),
                "ended_at": datetime(2026, 9, 24, 19, 40, tzinfo=timezone.utc).isoformat(),
            }
        )
        now = datetime(2026, 9, 24, 19, 41, tzinfo=timezone.utc)
        repo.now_iso = now.isoformat()

        service.sign_out(WORKSPACE_ID, utc_offset_minutes=330, now=now)

        day, values = repo.daily_writes[0]
        assert day == date(2026, 9, 25)
        assert values["login_seconds"] == 60 * 60

    def test_a_second_heartbeat_inside_the_refresh_window_does_not_rewrite(self):
        service, repo = make()
        heartbeat(service, repo, 0)
        writes = len(repo.daily_writes)

        heartbeat(service, repo, 1)
        heartbeat(service, repo, 4)

        assert len(repo.daily_writes) == writes

    def test_a_heartbeat_after_the_refresh_window_rewrites(self):
        service, repo = make()
        heartbeat(service, repo, 0)
        writes = len(repo.daily_writes)

        heartbeat(service, repo, ROLLUP_REFRESH.total_seconds() / 60 + 0.5)

        assert len(repo.daily_writes) == writes + 1

    def test_starting_and_ending_a_break_always_rewrite_the_rollup(self):
        service, repo = make()
        heartbeat(service, repo, 0)
        writes = len(repo.daily_writes)

        service.start_break(WORKSPACE_ID, now=at(1))
        service.end_break(WORKSPACE_ID, now=at(2))

        assert len(repo.daily_writes) == writes + 2

    def test_the_first_write_of_a_new_day_also_closes_out_yesterday_if_it_had_activity(self):
        service, repo = make()
        # Yesterday's session.
        repo.sessions.append(
            {
                "id": "old",
                "started_at": (at(0) - timedelta(days=1)).isoformat(),
                "last_seen_at": (at(0) - timedelta(days=1) + timedelta(hours=2)).isoformat(),
                "ended_at": (at(0) - timedelta(days=1) + timedelta(hours=2)).isoformat(),
            }
        )

        heartbeat(service, repo, 0)

        days = [d for d, _ in repo.daily_writes]
        assert days == [date(2026, 9, 24), date(2026, 9, 23)]
        assert repo.daily_writes[1][1]["login_seconds"] == 2 * 3600

    def test_yesterday_is_not_written_when_it_had_no_activity(self):
        """A brand-new member must not get an all-zero row for a day before they existed."""
        service, repo = make()

        heartbeat(service, repo, 0)

        assert [d for d, _ in repo.daily_writes] == [date(2026, 9, 24)]

    def test_yesterday_is_only_closed_out_on_the_first_write_of_the_day(self):
        service, repo = make()
        heartbeat(service, repo, 0)
        writes = len(repo.daily_writes)

        heartbeat(service, repo, ROLLUP_REFRESH.total_seconds() / 60 + 1)

        assert len(repo.daily_writes) == writes + 1  # today only

    def test_the_stored_values_match_the_computed_totals(self):
        service, repo = make(calls=[call_row(10, 11, 21)])
        beat(service, repo, 0, 60)

        service.sign_out(WORKSPACE_ID, now=at(61))

        values = repo.daily_writes[-1][1]
        assert values["login_seconds"] == 61 * 60
        assert values["talk_seconds"] == 10 * 60
        assert values["wrap_up_seconds"] == 120


class TestListDaily:
    def test_returns_the_stored_rows_in_the_range(self):
        service, repo = make()
        repo.daily[date(2026, 9, 23)] = {"login_seconds": 1}
        repo.daily[date(2026, 9, 24)] = {"login_seconds": 2}
        repo.daily[date(2026, 9, 26)] = {"login_seconds": 3}

        rows = service.list_daily(WORKSPACE_ID, since_day=date(2026, 9, 23), until_day=date(2026, 9, 25))

        assert sorted(r["login_seconds"] for r in rows) == [1, 2]

    def test_rejects_a_reversed_range(self):
        service, _ = make()

        with pytest.raises(ValidationError):
            service.list_daily(WORKSPACE_ID, since_day=date(2026, 9, 25), until_day=date(2026, 9, 24))

    def test_a_single_day_range_is_valid(self):
        service, repo = make()
        repo.daily[date(2026, 9, 24)] = {"login_seconds": 5}

        assert len(service.list_daily(WORKSPACE_ID, since_day=date(2026, 9, 24), until_day=date(2026, 9, 24))) == 1


def test_parse_helper_roundtrips_the_iso_strings_the_service_writes():
    """The service writes datetime.isoformat() and reads it back with parse_supabase_datetime."""
    assert parse_supabase_datetime(at(7).isoformat()) == at(7)
