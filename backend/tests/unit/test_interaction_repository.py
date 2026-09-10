from uuid import uuid4

import pytest

from app.core.exceptions import ConflictError
from app.repositories.lead_reference import InteractionRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()


def test_list_for_lead_returns_rows():
    client = FakeSupabaseClient(
        table_responses={"interactions": FakeResponse(data=[{"id": "i1", "type": "note", "payload": {}}])}
    )
    repo = InteractionRepository(client)

    rows = repo.list_for_lead(WORKSPACE_ID, LEAD_ID)

    assert len(rows) == 1
    assert client.table_calls == ["interactions"]


def test_count_for_lead_returns_the_configured_count():
    """Added in Phase 8 for the unified timeline's per-source total."""
    client = FakeSupabaseClient(table_responses={"interactions": FakeResponse(data=[{"id": "i1"}], count=5)})
    repo = InteractionRepository(client)

    assert repo.count_for_lead(WORKSPACE_ID, LEAD_ID) == 5


def test_create_note_inserts_a_type_note_row():
    """Added in Phase 8 §7 — the minimum note-creation capability, an
    `interactions` row with type='note' (no separate notes table)."""
    client = FakeSupabaseClient(
        table_responses={
            "interactions": FakeResponse(data=[{"id": "i1", "type": "note", "payload": {"text": "Called back"}}])
        }
    )
    repo = InteractionRepository(client)

    row = repo.create_note(WORKSPACE_ID, LEAD_ID, actor_member_id=str(uuid4()), text="Called back")

    assert row["type"] == "note"
    assert row["payload"]["text"] == "Called back"


def test_create_note_raises_conflict_when_insert_returns_no_rows():
    client = FakeSupabaseClient(table_responses={"interactions": FakeResponse(data=[])})
    repo = InteractionRepository(client)

    with pytest.raises(ConflictError):
        repo.create_note(WORKSPACE_ID, LEAD_ID, actor_member_id=str(uuid4()), text="x")


def test_create_status_change_inserts_a_type_status_change_row():
    """Phase 18 §"Conversion Activity" — reuses the existing
    type='status_change' vocabulary value (never written before this
    phase), same insert shape as create_note above."""
    client = FakeSupabaseClient(
        table_responses={
            "interactions": FakeResponse(
                data=[{"id": "i1", "type": "status_change", "payload": {"event": "converted_to_customer"}}]
            )
        }
    )
    repo = InteractionRepository(client)

    row = repo.create_status_change(
        WORKSPACE_ID, LEAD_ID, actor_member_id=str(uuid4()), payload={"event": "converted_to_customer"}
    )

    assert row["type"] == "status_change"
    assert row["payload"]["event"] == "converted_to_customer"


def test_create_status_change_raises_conflict_when_insert_returns_no_rows():
    client = FakeSupabaseClient(table_responses={"interactions": FakeResponse(data=[])})
    repo = InteractionRepository(client)

    with pytest.raises(ConflictError):
        repo.create_status_change(WORKSPACE_ID, LEAD_ID, actor_member_id=str(uuid4()), payload={})
