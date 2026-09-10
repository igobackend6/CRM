from uuid import uuid4

import pytest

import app.services.messaging.service as messaging_service_module
from app.core.exceptions import NotFoundError, ValidationError
from app.services.messaging.service import MessagingService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()
CONVERSATION_ID = uuid4()
SENDER_ID = str(uuid4())
OWNER_ID = str(uuid4())
MESSAGE_ID = str(uuid4())


def _lead_row(**overrides):
    row = {
        "id": str(LEAD_ID),
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "assigned_member_id": None,
    }
    row.update(overrides)
    return row


def _conversation_row(**overrides):
    row = {
        "id": str(CONVERSATION_ID),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": str(LEAD_ID),
        "created_by_member_id": SENDER_ID,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _message_row(**overrides):
    row = {
        "id": MESSAGE_ID,
        "workspace_id": str(WORKSPACE_ID),
        "conversation_id": str(CONVERSATION_ID),
        "sender_member_id": SENDER_ID,
        "body": "Hello there",
        "created_at": "2026-01-01T00:00:00Z",
        "read_at": None,
    }
    row.update(overrides)
    return row


def _client(**table_responses):
    return FakeSupabaseClient(
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "conversations": FakeResponse(data=[_conversation_row()]),
            "messages": FakeResponse(data=[_message_row()], count=1),
            "workspace_members": FakeResponse(data=[{"id": SENDER_ID, "profile": {"full_name": "Agent Smith"}}]),
            **table_responses,
        },
        rpc_responses={"current_member_id": SENDER_ID},
    )


# ---- get_or_create_conversation ----


def test_get_or_create_returns_the_existing_conversation_without_inserting():
    client = _client()
    service = MessagingService(client)

    result = service.get_or_create_conversation(WORKSPACE_ID, LEAD_ID)

    assert result["id"] == str(CONVERSATION_ID)
    assert result["lead"]["name"] == "Acme Corp"


def test_get_or_create_creates_one_when_none_exists():
    captured: dict = {}

    class _CapturingConversations:
        def get_for_lead(self, workspace_id, lead_id):
            return None

        def create_for_lead(self, workspace_id, lead_id, *, created_by_member_id):
            captured["lead_id"] = str(lead_id)
            captured["created_by_member_id"] = created_by_member_id
            return _conversation_row()

        def list_for_workspace(self, *a, **k):
            return [], 0

    client = _client()
    service = MessagingService(client)
    service._conversations = _CapturingConversations()

    result = service.get_or_create_conversation(WORKSPACE_ID, LEAD_ID)

    assert captured["lead_id"] == str(LEAD_ID)
    assert captured["created_by_member_id"] == SENDER_ID
    assert result["id"] == str(CONVERSATION_ID)


def test_get_or_create_rejects_a_lead_from_another_workspace():
    client = _client(leads=FakeResponse(data=None))
    service = MessagingService(client)

    with pytest.raises(NotFoundError):
        service.get_or_create_conversation(WORKSPACE_ID, uuid4())


# ---- list_conversations ----


def test_list_conversations_enriches_lead_name_preview_and_unread_count():
    client = _client(
        conversations=FakeResponse(data=[_conversation_row()], count=1),
        messages=FakeResponse(
            data=[_message_row(sender_member_id=OWNER_ID, body="Latest preview", read_at=None)],
        ),
    )
    service = MessagingService(client)

    items, total = service.list_conversations(WORKSPACE_ID, limit=20, offset=0)

    assert total == 1
    assert items[0]["lead"]["name"] == "Acme Corp"
    assert items[0]["latest_message_preview"] == "Latest preview"
    assert items[0]["unread_count"] == 1


def test_list_conversations_returns_empty_when_none_exist():
    client = _client(conversations=FakeResponse(data=[], count=0))
    service = MessagingService(client)

    items, total = service.list_conversations(WORKSPACE_ID, limit=20, offset=0)

    assert items == []
    assert total == 0


# ---- list_messages ----


def test_list_messages_validates_the_conversation_belongs_to_the_workspace():
    client = _client(conversations=FakeResponse(data=None))
    service = MessagingService(client)

    with pytest.raises(NotFoundError):
        service.list_messages(WORKSPACE_ID, uuid4(), limit=20, offset=0)


def test_list_messages_returns_enriched_rows_with_sender_name():
    client = _client()
    service = MessagingService(client)

    items, total = service.list_messages(WORKSPACE_ID, CONVERSATION_ID, limit=20, offset=0)

    assert total == 1
    assert items[0]["sender_member"]["full_name"] == "Agent Smith"


# ---- send_message ----


def test_send_message_never_trusts_a_client_supplied_sender():
    client = _client()
    service = MessagingService(client)

    service.send_message(WORKSPACE_ID, CONVERSATION_ID, "Hello")

    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls


def test_send_message_rejects_a_conversation_from_another_workspace():
    client = _client(conversations=FakeResponse(data=None))
    service = MessagingService(client)

    with pytest.raises(NotFoundError):
        service.send_message(WORKSPACE_ID, uuid4(), "Hello")


def test_send_message_notifies_the_lead_owner_when_a_teammate_sends(monkeypatch):
    calls: list[dict] = []
    monkeypatch.setattr(messaging_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    client = _client(leads=FakeResponse(data=[_lead_row(assigned_member_id=OWNER_ID)]))
    service = MessagingService(client)

    # current_member_id defaults to SENDER_ID, different from OWNER_ID.
    service.send_message(WORKSPACE_ID, CONVERSATION_ID, "Hello")

    assert len(calls) == 1
    assert calls[0]["recipient_member_id"] == OWNER_ID
    assert calls[0]["type"] == "system"
    assert calls[0]["related_entity_type"] == "conversation"


def test_send_message_does_not_notify_when_the_owner_sends_their_own_message(monkeypatch):
    calls: list[dict] = []
    monkeypatch.setattr(messaging_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    client = _client(leads=FakeResponse(data=[_lead_row(assigned_member_id=SENDER_ID)]))
    service = MessagingService(client)

    service.send_message(WORKSPACE_ID, CONVERSATION_ID, "Hello")

    assert calls == []


def test_send_message_does_not_notify_when_the_lead_has_no_owner(monkeypatch):
    calls: list[dict] = []
    monkeypatch.setattr(messaging_service_module, "notify", lambda workspace_id, **kwargs: calls.append(kwargs))
    client = _client(leads=FakeResponse(data=[_lead_row(assigned_member_id=None)]))
    service = MessagingService(client)

    service.send_message(WORKSPACE_ID, CONVERSATION_ID, "Hello")

    assert calls == []


# ---- mark_conversation_read ----


def test_mark_conversation_read_validates_the_conversation_belongs_to_the_workspace():
    client = _client(conversations=FakeResponse(data=None))
    service = MessagingService(client)

    with pytest.raises(NotFoundError):
        service.mark_conversation_read(WORKSPACE_ID, uuid4())


def test_mark_conversation_read_returns_the_number_updated():
    client = _client(messages=FakeResponse(data=[_message_row(), _message_row()]))
    service = MessagingService(client)

    updated = service.mark_conversation_read(WORKSPACE_ID, CONVERSATION_ID)

    assert updated == 2


def test_current_member_id_raises_validation_error_when_unresolvable():
    client = FakeSupabaseClient(
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "conversations": FakeResponse(data=[_conversation_row()]),
            "messages": FakeResponse(data=[_message_row()], count=1),
        },
        rpc_responses={"current_member_id": None},
    )
    service = MessagingService(client)

    with pytest.raises(ValidationError):
        service.send_message(WORKSPACE_ID, CONVERSATION_ID, "Hello")
