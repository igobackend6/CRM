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
