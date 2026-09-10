from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
LEAD_ID = str(uuid4())
CONVERSATION_ID = str(uuid4())
MESSAGE_ID = str(uuid4())
SENDER_ID = str(uuid4())


def _lead_row():
    return {"id": LEAD_ID, "workspace_id": WORKSPACE_ID, "name": "Acme Corp", "assigned_member_id": None}


def _conversation_row(**overrides):
    row = {
        "id": CONVERSATION_ID,
        "workspace_id": WORKSPACE_ID,
        "lead_id": LEAD_ID,
        "created_by_member_id": SENDER_ID,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _message_row(**overrides):
    row = {
        "id": MESSAGE_ID,
        "workspace_id": WORKSPACE_ID,
        "conversation_id": CONVERSATION_ID,
        "sender_member_id": SENDER_ID,
        "body": "Hello there",
        "created_at": "2026-01-01T00:00:00Z",
        "read_at": None,
    }
    row.update(overrides)
    return row


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    """Same pattern as test_calls_endpoint.py's _install()."""
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "leads": FakeResponse(data=[_lead_row()]),
            "conversations": FakeResponse(data=[_conversation_row()], count=1),
            "messages": FakeResponse(data=[_message_row()], count=1),
            "workspace_members": FakeResponse(data=[{"id": SENDER_ID, "profile": {"full_name": "Agent Smith"}}]),
        },
        rpc_responses={
            "has_permission": has_permission,
            "is_workspace_member": is_member,
            "current_member_id": SENDER_ID,
        },
    )
    app.dependency_overrides[deps.get_current_user] = lambda: AuthenticatedUser(
        id=uuid4(), email="agent@example.com", access_token="fake-token"
    )
    app.dependency_overrides[deps.get_user_client] = lambda: fake_client
    return fake_client


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    app.dependency_overrides.clear()


@pytest.fixture
def client():
    return TestClient(app)


# ---- GET /conversations ----


def test_list_conversations_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations")
    assert response.status_code == 401


def test_list_conversations_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations")
    assert response.status_code == 403


def test_list_conversations_returns_workspace_scoped_items(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations")
    assert response.status_code == 200
    body = response.json()
    assert body["items"][0]["lead"]["id"] == LEAD_ID
    assert body["total"] == 1
    assert "conversations" in fake_client.table_calls


def test_list_conversations_supports_pagination_query_params(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations", params={"limit": 5, "offset": 10})
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 5
    assert body["offset"] == 10


# ---- GET /leads/{lead_id}/conversation ----


def test_get_lead_conversation_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/conversation")
    assert response.status_code == 401


def test_get_lead_conversation_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/conversation")
    assert response.status_code == 403


def test_get_lead_conversation_returns_the_conversation(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/conversation")
    assert response.status_code == 200
    assert response.json()["id"] == CONVERSATION_ID


def test_get_lead_conversation_reaches_the_get_or_create_service_path(client):
    """Endpoint-level wiring check: `conversations`/`leads` are both
    queried through the route. The get-or-create *branch itself*
    (create-when-missing vs. return-existing) is covered at the service
    layer — test_messaging_service.py — since FakeSupabaseClient
    responds identically to a SELECT and an INSERT on the same table, so
    it can't usefully distinguish "found" from "just created" here."""
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/conversation")
    assert response.status_code == 200
    assert response.json()["lead"]["id"] == LEAD_ID
    assert "conversations" in fake_client.table_calls
    assert "leads" in fake_client.table_calls


def test_get_lead_conversation_rejects_a_lead_from_another_workspace(client):
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=None),
            "conversations": FakeResponse(data=[]),
            "messages": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[]),
        },
    )
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{uuid4()}/conversation")
    assert response.status_code == 404


# ---- GET /conversations/{id}/messages ----


def test_list_messages_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages")
    assert response.status_code == 401


def test_list_messages_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages")
    assert response.status_code == 403


def test_list_messages_returns_the_conversations_history(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages")
    assert response.status_code == 200
    body = response.json()
    assert body["items"][0]["id"] == MESSAGE_ID
    assert body["total"] == 1
    assert "messages" in fake_client.table_calls


def test_list_messages_rejects_a_conversation_not_visible_in_this_workspace(client):
    """Models workspace isolation: a conversation id from another
    workspace looks identical to a missing one under RLS."""
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "conversations": FakeResponse(data=None),
            "messages": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[]),
        },
    )
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{uuid4()}/messages")
    assert response.status_code == 404


# ---- POST /conversations/{id}/messages ----


def test_send_message_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages", json={"body": "hi"})
    assert response.status_code == 401


def test_send_message_denied_without_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages", json={"body": "hi"})
    assert response.status_code == 403


def test_send_message_succeeds_for_an_authorized_user(client):
    fake_client = _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages", json={"body": "Hello there"}
    )
    assert response.status_code == 201
    assert response.json()["body"] == "Hello there"
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_send_message_ignores_a_client_supplied_sender(client):
    """§9: MessageCreate has no sender/workspace field at all — even if a
    client sends one, pydantic drops fields not declared on the schema,
    so current_member_id() is the only possible source."""
    fake_client = _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages",
        json={"body": "Hello there", "sender_member_id": str(uuid4()), "workspace_id": str(uuid4())},
    )
    assert response.status_code == 201
    assert response.json()["sender_member"]["id"] == SENDER_ID
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_send_message_rejects_an_empty_body(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages", json={"body": ""})
    assert response.status_code == 422


def test_send_message_rejects_a_whitespace_only_body(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages", json={"body": "   "})
    assert response.status_code == 422


def test_send_message_rejects_a_body_over_the_maximum_length(client):
    _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/messages", json={"body": "x" * 4001}
    )
    assert response.status_code == 422


def test_send_message_rejects_a_conversation_from_another_workspace(client):
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "conversations": FakeResponse(data=None),
            "messages": FakeResponse(data=[_message_row()]),
            "workspace_members": FakeResponse(data=[]),
        },
    )
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{uuid4()}/messages", json={"body": "hi"})
    assert response.status_code == 404


# ---- POST /conversations/{id}/read ----


def test_mark_read_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/read")
    assert response.status_code == 401


def test_mark_read_denied_without_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/read")
    assert response.status_code == 403


def test_mark_read_succeeds_for_an_authorized_user(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "conversations": FakeResponse(data=[_conversation_row()]),
        "messages": FakeResponse(data=[_message_row(), _message_row()]),
        "workspace_members": FakeResponse(data=[]),
    })
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{CONVERSATION_ID}/read")
    assert response.status_code == 200
    assert response.json()["updated"] == 2


def test_mark_read_rejects_a_conversation_from_another_workspace(client):
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "conversations": FakeResponse(data=None),
            "messages": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[]),
        },
    )
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/conversations/{uuid4()}/read")
    assert response.status_code == 404
