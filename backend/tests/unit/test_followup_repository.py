from uuid import uuid4

import pytest

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.repositories.followups import FollowUpRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
FOLLOW_UP_ID = uuid4()


def _row(**overrides):
    row = {
        "id": str(FOLLOW_UP_ID),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": str(uuid4()),
        "assigned_member_id": str(uuid4()),
        "created_by_member_id": str(uuid4()),
        "type": "call",
        "due_at": "2026-02-01T09:00:00Z",
        "status": "pending",
        "notes": None,
        "completed_at": None,
        "cancelled_at": None,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def test_list_for_workspace_returns_rows_and_total():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[_row()], count=1)})
    repo = FollowUpRepository(client)

    rows, total = repo.list_for_workspace(WORKSPACE_ID)

    assert len(rows) == 1
    assert total == 1


def test_get_for_workspace_returns_the_row():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[_row()])})
    repo = FollowUpRepository(client)

    row = repo.get_for_workspace(WORKSPACE_ID, FOLLOW_UP_ID)

    assert row["id"] == str(FOLLOW_UP_ID)


def test_get_for_workspace_raises_not_found_when_missing():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=None)})
    repo = FollowUpRepository(client)

    with pytest.raises(NotFoundError):
        repo.get_for_workspace(WORKSPACE_ID, FOLLOW_UP_ID)


def test_list_for_lead_scopes_by_lead_id():
    lead_id = uuid4()
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[_row(lead_id=str(lead_id))])})
    repo = FollowUpRepository(client)

    rows = repo.list_for_lead(WORKSPACE_ID, lead_id)

    assert len(rows) == 1


def test_create_for_workspace_returns_the_inserted_row():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[_row()])})
    repo = FollowUpRepository(client)

    row = repo.create_for_workspace(WORKSPACE_ID, {"lead_id": str(uuid4())})

    assert row["id"] == str(FOLLOW_UP_ID)


def test_create_for_workspace_raises_conflict_on_empty_response():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[])})
    repo = FollowUpRepository(client)

    with pytest.raises(ConflictError):
        repo.create_for_workspace(WORKSPACE_ID, {"lead_id": str(uuid4())})


def test_update_for_workspace_returns_the_updated_row():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[_row(status="completed")])})
    repo = FollowUpRepository(client)

    row = repo.update_for_workspace(WORKSPACE_ID, FOLLOW_UP_ID, {"status": "completed"})

    assert row["status"] == "completed"


def test_update_for_workspace_raises_not_found_when_nothing_matched():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[])})
    repo = FollowUpRepository(client)

    with pytest.raises(NotFoundError):
        repo.update_for_workspace(WORKSPACE_ID, FOLLOW_UP_ID, {"status": "completed"})


def test_list_recent_for_lead_returns_rows():
    """Added in Phase 8 for the unified timeline (ordered by created_at,
    unlike list_for_lead's due_at order)."""
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[_row()])})
    repo = FollowUpRepository(client)

    rows = repo.list_recent_for_lead(WORKSPACE_ID, uuid4(), limit=5)

    assert len(rows) == 1


def test_count_for_lead_returns_the_configured_count():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[_row()], count=2)})
    repo = FollowUpRepository(client)

    assert repo.count_for_lead(WORKSPACE_ID, uuid4()) == 2


# ---- Phase 17: count_completed ----


def test_count_completed_returns_the_configured_count():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[], count=4)})
    repo = FollowUpRepository(client)

    assert repo.count_completed(WORKSPACE_ID) == 4


def test_count_completed_accepts_a_member_and_date_window():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[], count=1)})
    repo = FollowUpRepository(client)

    count = repo.count_completed(
        WORKSPACE_ID,
        assigned_member_id=uuid4(),
        since="2026-01-01T00:00:00+00:00",
        until="2026-02-01T00:00:00+00:00",
    )

    assert count == 1
    assert client.table_calls == ["follow_ups"]


def test_count_completed_defaults_to_zero_when_nothing_matches():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[], count=None)})
    repo = FollowUpRepository(client)

    assert repo.count_completed(WORKSPACE_ID) == 0


# ---- Phase 19: map_next_pending_for_leads ----


def test_map_next_pending_for_leads_returns_empty_for_an_empty_id_list():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[_row()])})
    repo = FollowUpRepository(client)

    result = repo.map_next_pending_for_leads(WORKSPACE_ID, [])

    assert result == {}
    assert client.table_calls == []  # never even queries — nothing to look up


def test_map_next_pending_for_leads_keeps_only_the_earliest_row_per_lead():
    """`follow_ups` is ordered by `due_at` ascending, so the first row
    seen per `lead_id` is already its earliest — a second, later row for
    the same lead must not overwrite it."""
    lead_id = str(uuid4())
    client = FakeSupabaseClient(
        table_responses={
            "follow_ups": FakeResponse(
                data=[
                    _row(id="f1", lead_id=lead_id, due_at="2026-02-01T09:00:00Z"),
                    _row(id="f2", lead_id=lead_id, due_at="2026-03-01T09:00:00Z"),
                ]
            )
        }
    )
    repo = FollowUpRepository(client)

    result = repo.map_next_pending_for_leads(WORKSPACE_ID, [lead_id])

    assert result[lead_id]["id"] == "f1"
    assert client.table_calls == ["follow_ups"]


def test_map_next_pending_for_leads_omits_leads_with_no_pending_follow_up():
    client = FakeSupabaseClient(table_responses={"follow_ups": FakeResponse(data=[])})
    repo = FollowUpRepository(client)

    result = repo.map_next_pending_for_leads(WORKSPACE_ID, [str(uuid4())])

    assert result == {}
