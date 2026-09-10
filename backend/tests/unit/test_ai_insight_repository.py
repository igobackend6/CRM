from uuid import uuid4

import pytest

from app.core.exceptions import NotFoundError
from app.repositories.ai_insights import AIInsightRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
CALL_ID = str(uuid4())


def _row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "call_id": CALL_ID,
        "requested_by_member_id": str(uuid4()),
        "status": "pending",
        "action_items": [],
        "error_message": None,
        "requested_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def test_get_for_call_returns_the_row():
    client = FakeSupabaseClient(table_responses={"ai_call_insights": FakeResponse(data=[_row()])})
    repo = AIInsightRepository(client)

    row = repo.get_for_call(WORKSPACE_ID, CALL_ID)

    assert row["call_id"] == CALL_ID


def test_get_for_call_returns_none_when_nothing_requested_yet():
    client = FakeSupabaseClient(table_responses={"ai_call_insights": FakeResponse(data=None)})
    repo = AIInsightRepository(client)

    assert repo.get_for_call(WORKSPACE_ID, CALL_ID) is None


def test_upsert_pending_inserts_a_fresh_row_when_none_exists():
    client = FakeSupabaseClient(table_responses={"ai_call_insights": FakeResponse(data=[_row(status="pending")])})
    repo = AIInsightRepository(client)

    row = repo.upsert_pending(WORKSPACE_ID, CALL_ID, requested_by_member_id="m1")

    assert row["call_id"] == CALL_ID
    assert "ai_call_insights" in client.table_calls


def test_update_for_call_returns_the_updated_row():
    client = FakeSupabaseClient(table_responses={"ai_call_insights": FakeResponse(data=[_row(status="completed")])})
    repo = AIInsightRepository(client)

    row = repo.update_for_call(WORKSPACE_ID, CALL_ID, {"status": "completed"})

    assert row["status"] == "completed"


def test_update_for_call_raises_not_found_when_nothing_matches():
    client = FakeSupabaseClient(table_responses={"ai_call_insights": FakeResponse(data=[])})
    repo = AIInsightRepository(client)

    with pytest.raises(NotFoundError):
        repo.update_for_call(WORKSPACE_ID, CALL_ID, {"status": "completed"})


def test_list_for_calls_maps_call_id_to_its_insight_row():
    other_call_id = str(uuid4())
    client = FakeSupabaseClient(
        table_responses={"ai_call_insights": FakeResponse(data=[_row(call_id=CALL_ID), _row(call_id=other_call_id)])}
    )
    repo = AIInsightRepository(client)

    result = repo.list_for_calls(WORKSPACE_ID, [CALL_ID, other_call_id])

    assert set(result.keys()) == {CALL_ID, other_call_id}


def test_list_for_calls_returns_empty_for_an_empty_id_list():
    client = FakeSupabaseClient(table_responses={"ai_call_insights": FakeResponse(data=[_row()])})
    repo = AIInsightRepository(client)

    result = repo.list_for_calls(WORKSPACE_ID, [])

    assert result == {}
    assert client.table_calls == []
