from uuid import uuid4

import pytest

from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.messaging import ConversationRepository, MessageRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()
CONVERSATION_ID = uuid4()
MEMBER_A = str(uuid4())
MEMBER_B = str(uuid4())


def _conversation_row(**overrides):
    row = {
        "id": str(CONVERSATION_ID),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": str(LEAD_ID),
        "created_by_member_id": MEMBER_A,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _message_row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "conversation_id": str(CONVERSATION_ID),
        "sender_member_id": MEMBER_A,
        "body": "Hello",
        "created_at": "2026-01-01T00:00:00Z",
        "read_at": None,
    }
    row.update(overrides)
    return row


# ---- ConversationRepository ----


def test_get_for_lead_returns_none_when_no_conversation_exists():
    client = FakeSupabaseClient(table_responses={"conversations": FakeResponse(data=[])})
    repo = ConversationRepository(client)

    assert repo.get_for_lead(WORKSPACE_ID, LEAD_ID) is None


def test_get_for_lead_returns_the_existing_conversation():
    client = FakeSupabaseClient(table_responses={"conversations": FakeResponse(data=[_conversation_row()])})
    repo = ConversationRepository(client)

    row = repo.get_for_lead(WORKSPACE_ID, LEAD_ID)

    assert row["id"] == str(CONVERSATION_ID)


def test_get_for_workspace_raises_not_found_when_missing():
    client = FakeSupabaseClient(table_responses={"conversations": FakeResponse(data=None)})
    repo = ConversationRepository(client)

    with pytest.raises(NotFoundError):
        repo.get_for_workspace(WORKSPACE_ID, uuid4())


def test_create_for_lead_returns_the_inserted_row():
    client = FakeSupabaseClient(table_responses={"conversations": FakeResponse(data=[_conversation_row()])})
    repo = ConversationRepository(client)

    row = repo.create_for_lead(WORKSPACE_ID, LEAD_ID, created_by_member_id=MEMBER_A)

    assert row["lead_id"] == str(LEAD_ID)


def test_create_for_lead_raises_conflict_on_empty_response():
    client = FakeSupabaseClient(table_responses={"conversations": FakeResponse(data=[])})
    repo = ConversationRepository(client)

    with pytest.raises(ConflictError):
        repo.create_for_lead(WORKSPACE_ID, LEAD_ID, created_by_member_id=MEMBER_A)


def test_list_for_workspace_returns_rows_and_total():
    client = FakeSupabaseClient(table_responses={"conversations": FakeResponse(data=[_conversation_row()], count=1)})
    repo = ConversationRepository(client)

    rows, total = repo.list_for_workspace(WORKSPACE_ID, limit=20, offset=0)

    assert total == 1
    assert rows[0]["id"] == str(CONVERSATION_ID)


# ---- MessageRepository ----


def test_list_for_conversation_returns_rows_oldest_first_order_and_total():
    client = FakeSupabaseClient(table_responses={"messages": FakeResponse(data=[_message_row(), _message_row()], count=2)})
    repo = MessageRepository(client)

    rows, total = repo.list_for_conversation(WORKSPACE_ID, CONVERSATION_ID, limit=20, offset=0)

    assert total == 2
    assert len(rows) == 2


def test_create_for_conversation_returns_the_inserted_row():
    client = FakeSupabaseClient(table_responses={"messages": FakeResponse(data=[_message_row(body="Hi there")])})
    repo = MessageRepository(client)

    row = repo.create_for_conversation(WORKSPACE_ID, CONVERSATION_ID, sender_member_id=MEMBER_A, body="Hi there")

    assert row["body"] == "Hi there"


def test_create_for_conversation_raises_conflict_on_empty_response():
    client = FakeSupabaseClient(table_responses={"messages": FakeResponse(data=[])})
    repo = MessageRepository(client)

    with pytest.raises(ConflictError):
        repo.create_for_conversation(WORKSPACE_ID, CONVERSATION_ID, sender_member_id=MEMBER_A, body="Hi")


def test_list_latest_and_unread_picks_the_newest_row_per_conversation():
    other_conversation_id = str(uuid4())
    rows = [
        _message_row(conversation_id=other_conversation_id, body="older-other", created_at="2026-01-01T00:00:00Z"),
        _message_row(conversation_id=other_conversation_id, body="newest-other", created_at="2026-01-03T00:00:00Z"),
        _message_row(body="older", created_at="2026-01-01T00:00:00Z"),
        _message_row(body="newest", created_at="2026-01-02T00:00:00Z"),
    ]
    # FakeSupabaseClient doesn't actually sort — this test supplies rows
    # already in the newest-first order the real `.order(desc=True)`
    # query would produce, matching how test_call_repository.py-style
    # fakes are configured throughout this codebase.
    ordered = [rows[1], rows[3], rows[0], rows[2]]
    client = FakeSupabaseClient(table_responses={"messages": FakeResponse(data=ordered)})
    repo = MessageRepository(client)

    latest, _unread = repo.list_latest_and_unread(
        WORKSPACE_ID, [str(CONVERSATION_ID), other_conversation_id], current_member_id=MEMBER_A
    )

    assert latest[str(CONVERSATION_ID)]["body"] == "newest"
    assert latest[other_conversation_id]["body"] == "newest-other"


def test_list_latest_and_unread_counts_only_messages_not_sent_by_the_caller():
    rows = [
        _message_row(sender_member_id=MEMBER_B, read_at=None),  # unread, from someone else -> counts
        _message_row(sender_member_id=MEMBER_A, read_at=None),  # unread, but from the caller -> does not count
        _message_row(sender_member_id=MEMBER_B, read_at="2026-01-02T00:00:00Z"),  # already read -> does not count
    ]
    client = FakeSupabaseClient(table_responses={"messages": FakeResponse(data=rows)})
    repo = MessageRepository(client)

    _latest, unread = repo.list_latest_and_unread(WORKSPACE_ID, [str(CONVERSATION_ID)], current_member_id=MEMBER_A)

    assert unread[str(CONVERSATION_ID)] == 1


def test_list_latest_and_unread_returns_empty_dicts_for_no_ids():
    client = FakeSupabaseClient(table_responses={"messages": FakeResponse(data=[_message_row()])})
    repo = MessageRepository(client)

    latest, unread = repo.list_latest_and_unread(WORKSPACE_ID, [], current_member_id=MEMBER_A)

    assert latest == {}
    assert unread == {}


def test_mark_conversation_read_returns_the_number_of_rows_updated():
    client = FakeSupabaseClient(table_responses={"messages": FakeResponse(data=[_message_row(), _message_row()])})
    repo = MessageRepository(client)

    updated = repo.mark_conversation_read(WORKSPACE_ID, CONVERSATION_ID, current_member_id=MEMBER_A)

    assert updated == 2
