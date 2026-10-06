from uuid import uuid4

import pytest

from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.calls import CallRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()


def _row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": str(LEAD_ID),
        "agent_member_id": str(uuid4()),
        "direction": "outbound",
        "state": "ENDED",
        "outcome_id": None,
        "started_at": "2026-01-01T00:00:00Z",
        "connected_at": None,
        "ended_at": None,
        "duration_seconds": None,
        "notes": None,
        "created_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def test_list_recent_for_lead_returns_rows():
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[_row(), _row()])})
    repo = CallRepository(client)

    rows = repo.list_recent_for_lead(WORKSPACE_ID, LEAD_ID, limit=10)

    assert len(rows) == 2
    assert client.table_calls == ["calls"]


def test_list_recent_for_lead_returns_empty_when_no_calls_exist():
    """Phase 8 §5: calling itself is out of scope (Phase 9), so this
    table is genuinely empty in every environment this phase runs in —
    the repository must return an empty list, never fabricated rows."""
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[])})
    repo = CallRepository(client)

    assert repo.list_recent_for_lead(WORKSPACE_ID, LEAD_ID) == []


def test_count_for_lead_returns_the_configured_count():
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[_row()], count=3)})
    repo = CallRepository(client)

    assert repo.count_for_lead(WORKSPACE_ID, LEAD_ID) == 3


# ---- Phase 9: list_for_workspace / get_for_workspace / create_for_workspace ----


def test_list_for_workspace_returns_rows_and_total():
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[_row(), _row()], count=2)})
    repo = CallRepository(client)

    rows, total = repo.list_for_workspace(WORKSPACE_ID)

    assert len(rows) == 2
    assert total == 2


def test_get_for_workspace_returns_the_row():
    call_id = uuid4()
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[_row(id=str(call_id))])})
    repo = CallRepository(client)

    row = repo.get_for_workspace(WORKSPACE_ID, call_id)

    assert row["id"] == str(call_id)


def test_get_for_workspace_raises_not_found_when_missing():
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=None)})
    repo = CallRepository(client)

    with pytest.raises(NotFoundError):
        repo.get_for_workspace(WORKSPACE_ID, uuid4())


def test_create_for_workspace_returns_the_inserted_row():
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[_row()])})
    repo = CallRepository(client)

    row = repo.create_for_workspace(WORKSPACE_ID, {"lead_id": str(LEAD_ID), "direction": "outbound", "state": "ENDED"})

    assert row["lead_id"] == str(LEAD_ID)


def test_create_for_workspace_raises_conflict_on_empty_response():
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[])})
    repo = CallRepository(client)

    with pytest.raises(ConflictError):
        repo.create_for_workspace(WORKSPACE_ID, {"lead_id": str(LEAD_ID), "direction": "outbound", "state": "ENDED"})


# ---- Phase 17: count_filtered ----


def test_count_filtered_returns_the_configured_count():
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[], count=6)})
    repo = CallRepository(client)

    assert repo.count_filtered(WORKSPACE_ID) == 6


def test_count_filtered_accepts_every_optional_filter_without_error():
    """Proves the method builds a valid query with every optional filter
    combined (agent_member_id + since + until + states) — the fake
    doesn't apply filters (see its own docstring), so this checks wiring,
    not that Postgres would narrow the result."""
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[], count=2)})
    repo = CallRepository(client)

    count = repo.count_filtered(
        WORKSPACE_ID,
        agent_member_id=uuid4(),
        since="2026-01-01T00:00:00+00:00",
        until="2026-02-01T00:00:00+00:00",
        states=["CONNECTED", "ENDED"],
    )

    assert count == 2
    assert client.table_calls == ["calls"]


def test_count_filtered_defaults_to_zero_when_nothing_matches():
    client = FakeSupabaseClient(table_responses={"calls": FakeResponse(data=[], count=None)})
    repo = CallRepository(client)

    assert repo.count_filtered(WORKSPACE_ID) == 0


# ---- Analytics hub: list_for_trends ----


class _SequencedCallsClient:
    """Hands out a different response per `.table("calls")` call and
    records every builder call — the shared FakeSupabaseClient always
    returns one fixed response per table, which can't express "page 1 is
    full, page 2 is short" or let a test see which filters were applied."""

    def __init__(self, pages):
        self._pages = list(pages)
        self.builders = []

    def table(self, name):
        assert name == "calls"
        response = FakeResponse(data=self._pages.pop(0) if self._pages else [])
        builder = _RecordingBuilder(response)
        self.builders.append(builder)
        return builder


class _RecordingBuilder:
    def __init__(self, response):
        self._response = response
        self.calls = []

    def __getattr__(self, name):
        def _record(*args, **kwargs):
            self.calls.append((name, args))
            return self

        return _record

    def execute(self):
        return self._response


def _trend_row(**overrides):
    row = {"started_at": "2026-09-24T05:30:00+00:00", "state": "ENDED", "lead_id": str(LEAD_ID), "duration_seconds": 60}
    row.update(overrides)
    return row


_MEMBER = str(uuid4())
_SINCE = "2026-09-24T00:00:00+00:00"
_UNTIL = "2026-09-25T00:00:00+00:00"


def test_list_for_trends_returns_a_short_first_page_in_one_query():
    client = _SequencedCallsClient([[_trend_row(), _trend_row()]])

    rows = CallRepository(client).list_for_trends(
        WORKSPACE_ID, agent_member_id=_MEMBER, since=_SINCE, until=_UNTIL
    )

    assert len(rows) == 2
    assert len(client.builders) == 1


def test_list_for_trends_pages_until_a_short_page_so_a_busy_month_is_not_truncated():
    """PostgREST caps one response at 1000 rows; a page of exactly 1000
    means "there may be more", so the repository must ask again."""
    client = _SequencedCallsClient([[_trend_row()] * 1000, [_trend_row()] * 3])

    rows = CallRepository(client).list_for_trends(
        WORKSPACE_ID, agent_member_id=_MEMBER, since=_SINCE, until=_UNTIL
    )

    assert len(rows) == 1003
    assert len(client.builders) == 2
    # The second query must ask for the next window of rows, not repeat page 1.
    assert ("range", (1000, 1999)) in client.builders[1].calls


def test_list_for_trends_stops_after_an_exactly_full_final_page_returns_empty():
    client = _SequencedCallsClient([[_trend_row()] * 1000, []])

    rows = CallRepository(client).list_for_trends(
        WORKSPACE_ID, agent_member_id=_MEMBER, since=_SINCE, until=_UNTIL
    )

    assert len(rows) == 1000
    assert len(client.builders) == 2


def test_list_for_trends_only_filters_on_direction_when_one_is_given():
    all_client = _SequencedCallsClient([[]])
    CallRepository(all_client).list_for_trends(WORKSPACE_ID, agent_member_id=_MEMBER, since=_SINCE, until=_UNTIL)
    inbound_client = _SequencedCallsClient([[]])
    CallRepository(inbound_client).list_for_trends(
        WORKSPACE_ID, agent_member_id=_MEMBER, since=_SINCE, until=_UNTIL, direction="inbound"
    )

    assert not any(name == "eq" and args[0] == "direction" for name, args in all_client.builders[0].calls)
    assert ("eq", ("direction", "inbound")) in inbound_client.builders[0].calls


def test_list_for_trends_is_scoped_to_the_workspace_agent_and_window():
    client = _SequencedCallsClient([[]])

    CallRepository(client).list_for_trends(WORKSPACE_ID, agent_member_id=_MEMBER, since=_SINCE, until=_UNTIL)

    calls = client.builders[0].calls
    assert ("eq", ("workspace_id", str(WORKSPACE_ID))) in calls
    assert ("eq", ("agent_member_id", _MEMBER)) in calls
    assert ("gte", ("started_at", _SINCE)) in calls
    assert ("lt", ("started_at", _UNTIL)) in calls
