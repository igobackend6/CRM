from datetime import date
from uuid import uuid4

import pytest
from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError
from app.repositories.activity import ActivityRepository
from app.repositories.calls import CallRepository
from tests.support.fake_supabase import FakeResponse

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
SINCE = "2026-09-24T00:00:00+00:00"
UNTIL = "2026-09-25T00:00:00+00:00"


class _RecordingBuilder:
    """Records every builder call and resolves to a configured response (or
    raises a configured error) — the shared fake returns one fixed response
    per table and cannot show which filters were applied."""

    def __init__(self, response, error=None):
        self._response = response
        self._error = error
        self.calls: list[tuple[str, tuple]] = []

    def __getattr__(self, name):
        def _record(*args, **kwargs):
            self.calls.append((name, args))
            return self

        return _record

    def execute(self):
        if self._error is not None:
            raise self._error
        return self._response


class _RecordingClient:
    def __init__(self, tables=None, error=None):
        self._tables = tables or {}
        self._error = error
        self.builders: list[tuple[str, _RecordingBuilder]] = []

    def table(self, name):
        builder = _RecordingBuilder(self._tables.get(name, FakeResponse(data=[])), self._error)
        self.builders.append((name, builder))
        return builder

    def last(self, table):
        return next(b for n, b in reversed(self.builders) if n == table)


def repo(tables=None, error=None):
    client = _RecordingClient(tables, error)
    return ActivityRepository(client), client


# ---- sessions ----


def test_get_open_session_looks_for_this_members_row_with_no_end():
    r, client = repo({"agent_sessions": FakeResponse(data=[{"id": "s1", "ended_at": None}])})

    row = r.get_open_session(WORKSPACE_ID, MEMBER_ID)

    assert row == {"id": "s1", "ended_at": None}
    calls = client.last("agent_sessions").calls
    assert ("eq", ("workspace_id", str(WORKSPACE_ID))) in calls
    assert ("eq", ("member_id", MEMBER_ID)) in calls
    assert ("is_", ("ended_at", "null")) in calls


def test_get_open_session_is_none_when_there_is_none():
    r, _ = repo({"agent_sessions": FakeResponse(data=[])})

    assert r.get_open_session(WORKSPACE_ID, MEMBER_ID) is None


def test_open_session_inserts_started_and_last_seen_at_the_same_instant():
    r, client = repo({"agent_sessions": FakeResponse(data=[{"id": "s1"}])})

    r.open_session(WORKSPACE_ID, MEMBER_ID, SINCE)

    assert ("insert", ({"workspace_id": str(WORKSPACE_ID), "member_id": MEMBER_ID, "started_at": SINCE, "last_seen_at": SINCE},)) in client.last("agent_sessions").calls


def test_open_session_turns_the_one_open_per_member_violation_into_a_conflict():
    """The partial unique index is what stops two devices double-counting."""
    error = APIError({"message": "duplicate key", "code": "23505", "details": "", "hint": ""})
    r, _ = repo(error=error)

    with pytest.raises(ConflictError):
        r.open_session(WORKSPACE_ID, MEMBER_ID, SINCE)


def test_open_session_does_not_swallow_other_database_errors():
    error = APIError({"message": "permission denied", "code": "42501", "details": "", "hint": ""})
    r, _ = repo(error=error)

    with pytest.raises(APIError):
        r.open_session(WORKSPACE_ID, MEMBER_ID, SINCE)


def test_touch_and_close_update_the_right_row():
    r, client = repo()

    r.touch_session("s1", SINCE)
    r.close_session("s2", UNTIL)

    touch, close = (b.calls for n, b in client.builders if n == "agent_sessions")
    assert ("update", ({"last_seen_at": SINCE},)) in touch and ("eq", ("id", "s1")) in touch
    assert ("update", ({"ended_at": UNTIL},)) in close and ("eq", ("id", "s2")) in close


def test_list_sessions_asks_for_sessions_overlapping_the_window():
    r, client = repo()

    r.list_sessions(WORKSPACE_ID, MEMBER_ID, SINCE, UNTIL)

    calls = client.last("agent_sessions").calls
    assert ("lt", ("started_at", UNTIL)) in calls
    # Ended at/after the start of the window, or still open.
    assert ("or_", (f"ended_at.gte.{SINCE},ended_at.is.null",)) in calls


# ---- breaks ----


def test_open_break_inserts_a_row_for_this_member():
    r, client = repo({"agent_breaks": FakeResponse(data=[{"id": "b1"}])})

    r.open_break(WORKSPACE_ID, MEMBER_ID, SINCE)

    assert ("insert", ({"workspace_id": str(WORKSPACE_ID), "member_id": MEMBER_ID, "started_at": SINCE},)) in client.last("agent_breaks").calls


def test_open_break_conflict_when_one_is_already_open():
    error = APIError({"message": "duplicate key", "code": "23505", "details": "", "hint": ""})
    r, _ = repo(error=error)

    with pytest.raises(ConflictError):
        r.open_break(WORKSPACE_ID, MEMBER_ID, SINCE)


def test_get_open_break_filters_on_no_end():
    r, client = repo()

    assert r.get_open_break(WORKSPACE_ID, MEMBER_ID) is None
    assert ("is_", ("ended_at", "null")) in client.last("agent_breaks").calls


def test_close_break_and_list_breaks():
    r, client = repo()

    r.close_break("b1", UNTIL)
    r.list_breaks(WORKSPACE_ID, MEMBER_ID, SINCE, UNTIL)

    close, listing = (b.calls for n, b in client.builders if n == "agent_breaks")
    assert ("update", ({"ended_at": UNTIL},)) in close
    assert ("lt", ("started_at", UNTIL)) in listing
    assert ("or_", (f"ended_at.gte.{SINCE},ended_at.is.null",)) in listing


# ---- daily rollup ----


def test_get_daily_looks_up_one_member_one_day():
    r, client = repo({"agent_daily_activity": FakeResponse(data=[{"login_seconds": 5}])})

    assert r.get_daily(WORKSPACE_ID, MEMBER_ID, date(2026, 9, 24)) == {"login_seconds": 5}
    assert ("eq", ("day", "2026-09-24")) in client.last("agent_daily_activity").calls


def test_upsert_daily_is_keyed_on_workspace_member_and_day():
    r, client = repo()

    r.upsert_daily(WORKSPACE_ID, MEMBER_ID, date(2026, 9, 24), {"login_seconds": 60})

    calls = client.last("agent_daily_activity").calls
    row = {"workspace_id": str(WORKSPACE_ID), "member_id": MEMBER_ID, "day": "2026-09-24", "login_seconds": 60}
    assert ("upsert", (row,)) in calls


def test_list_daily_covers_the_range_inclusively_newest_first():
    r, client = repo()

    r.list_daily(WORKSPACE_ID, date(2026, 9, 1), date(2026, 9, 30))

    calls = client.last("agent_daily_activity").calls
    assert ("gte", ("day", "2026-09-01")) in calls
    assert ("lte", ("day", "2026-09-30")) in calls
    assert not any(name == "eq" and args[0] == "member_id" for name, args in calls)


def test_list_daily_can_be_narrowed_to_one_member():
    r, client = repo()

    r.list_daily(WORKSPACE_ID, date(2026, 9, 1), date(2026, 9, 30), member_id=MEMBER_ID)

    assert ("eq", ("member_id", MEMBER_ID)) in client.last("agent_daily_activity").calls


# ---- calls: list_for_activity ----


class _PagedCallsClient:
    def __init__(self, pages):
        self._pages = list(pages)
        self.builders: list[_RecordingBuilder] = []

    def table(self, name):
        assert name == "calls"
        builder = _RecordingBuilder(FakeResponse(data=self._pages.pop(0) if self._pages else []))
        self.builders.append(builder)
        return builder


def _call(i=0):
    return {"started_at": "2026-09-24T10:00:00+00:00", "connected_at": None, "ended_at": None}


def test_list_for_activity_is_scoped_and_widens_the_lower_bound_by_a_day():
    """A call that began just before `since` can still end inside the window."""
    client = _PagedCallsClient([[_call()]])

    rows = CallRepository(client).list_for_activity(WORKSPACE_ID, agent_member_id=MEMBER_ID, since=SINCE, until=UNTIL)

    assert len(rows) == 1
    calls = client.builders[0].calls
    assert ("eq", ("workspace_id", str(WORKSPACE_ID))) in calls
    assert ("eq", ("agent_member_id", MEMBER_ID)) in calls
    assert ("gte", ("started_at", "2026-09-23T00:00:00+00:00")) in calls
    assert ("lt", ("started_at", UNTIL)) in calls


def test_list_for_activity_pages_past_the_thousand_row_cap():
    client = _PagedCallsClient([[_call()] * 1000, [_call()] * 5])

    rows = CallRepository(client).list_for_activity(WORKSPACE_ID, agent_member_id=MEMBER_ID, since=SINCE, until=UNTIL)

    assert len(rows) == 1005
    assert len(client.builders) == 2
    assert ("range", (1000, 1999)) in client.builders[1].calls


def test_list_for_activity_accepts_a_z_suffixed_timestamp():
    """The mobile app sends ...Z; the lower bound must still be computed."""
    client = _PagedCallsClient([[]])

    CallRepository(client).list_for_activity(WORKSPACE_ID, agent_member_id=MEMBER_ID, since="2026-09-24T00:00:00Z", until=UNTIL)

    assert ("gte", ("started_at", "2026-09-23T00:00:00+00:00")) in client.builders[0].calls
