from uuid import uuid4

import pytest

from app.core.exceptions import NotFoundError
from app.repositories.notifications import NotificationRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
NOTIFICATION_ID = uuid4()


def _row(**overrides):
    row = {
        "id": str(NOTIFICATION_ID),
        "workspace_id": str(WORKSPACE_ID),
        "recipient_member_id": MEMBER_ID,
        "type": "lead_assigned",
        "title": "Lead assigned to you",
        "body": "Acme Corp",
        "related_entity_type": "lead",
        "related_entity_id": str(uuid4()),
        "is_read": False,
        "read_at": None,
        "created_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def test_list_for_workspace_returns_rows_and_total():
    client = FakeSupabaseClient(table_responses={"notifications": FakeResponse(data=[_row()], count=1)})
    repo = NotificationRepository(client)

    rows, total = repo.list_for_workspace(WORKSPACE_ID, MEMBER_ID, limit=20, offset=0)

    assert total == 1
    assert rows[0]["id"] == str(NOTIFICATION_ID)
    assert "notifications" in client.table_calls


def test_get_for_workspace_returns_the_row():
    client = FakeSupabaseClient(table_responses={"notifications": FakeResponse(data=[_row()])})
    repo = NotificationRepository(client)

    row = repo.get_for_workspace(WORKSPACE_ID, MEMBER_ID, NOTIFICATION_ID)

    assert row["id"] == str(NOTIFICATION_ID)


def test_get_for_workspace_raises_not_found_when_missing_or_not_the_recipients():
    client = FakeSupabaseClient(table_responses={"notifications": FakeResponse(data=None)})
    repo = NotificationRepository(client)

    with pytest.raises(NotFoundError):
        repo.get_for_workspace(WORKSPACE_ID, MEMBER_ID, uuid4())


def test_mark_read_updates_is_read_and_read_at():
    client = FakeSupabaseClient(table_responses={"notifications": FakeResponse(data=[_row(is_read=True, read_at="2026-01-02T00:00:00Z")])})
    repo = NotificationRepository(client)

    row = repo.mark_read(WORKSPACE_ID, MEMBER_ID, NOTIFICATION_ID, is_read=True)

    assert row["is_read"] is True
    assert row["read_at"] is not None


def test_mark_read_raises_not_found_when_the_update_touches_no_row():
    client = FakeSupabaseClient(table_responses={"notifications": FakeResponse(data=[])})
    repo = NotificationRepository(client)

    with pytest.raises(NotFoundError):
        repo.mark_read(WORKSPACE_ID, MEMBER_ID, uuid4(), is_read=True)


def test_mark_all_read_returns_the_updated_count():
    client = FakeSupabaseClient(table_responses={"notifications": FakeResponse(data=[_row(), _row(id=str(uuid4()))])})
    repo = NotificationRepository(client)

    count = repo.mark_all_read(WORKSPACE_ID, MEMBER_ID)

    assert count == 2


def test_create_for_workspace_inserts_and_returns_the_row():
    client = FakeSupabaseClient(table_responses={"notifications": FakeResponse(data=[_row()])})
    repo = NotificationRepository(client)

    row = repo.create_for_workspace(
        WORKSPACE_ID,
        {
            "recipient_member_id": MEMBER_ID,
            "type": "lead_assigned",
            "title": "Lead assigned to you",
            "body": "Acme Corp",
            "related_entity_type": "lead",
            "related_entity_id": str(uuid4()),
        },
    )

    assert row["recipient_member_id"] == MEMBER_ID
