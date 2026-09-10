from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
MEMBER_ID = str(uuid4())
NOTIFICATION_ID = str(uuid4())


def _notification_row(**overrides):
    row = {
        "id": NOTIFICATION_ID,
        "workspace_id": WORKSPACE_ID,
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


def _install(*, has_permission: bool, table_responses=None):
    """Same pattern as test_calls_endpoint.py's _install()."""
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "notifications": FakeResponse(data=[_notification_row()], count=1),
        },
        rpc_responses={
            "has_permission": has_permission,
            "is_workspace_member": True,
            "current_member_id": MEMBER_ID,
        },
    )
    app.dependency_overrides[deps.get_current_user] = lambda: AuthenticatedUser(
        id=uuid4(), email="rep@example.com", access_token="fake-token"
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


# ---- GET /notifications ----


def test_list_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications")
    assert response.status_code == 401


def test_list_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications")
    assert response.status_code == 403


def test_list_returns_the_callers_own_notifications(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications")
    assert response.status_code == 200
    body = response.json()
    # NotificationOut deliberately has no recipient_member_id field —
    # every row returned here is implicitly "mine" (enforced by
    # NotificationService resolving the recipient as current_member_id()
    # server-side), so echoing it back would be redundant.
    assert body["items"][0]["title"] == "Lead assigned to you"
    assert body["total"] == 1
    assert "notifications" in fake_client.table_calls
    # The recipient is always resolved server-side, never accepted as a
    # request parameter — there is no recipient/member query param on
    # this route at all (§9 "never trust actor/member identity from the
    # client").
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_list_supports_pagination_query_params(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications", params={"limit": 5, "offset": 10})
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 5
    assert body["offset"] == 10


def test_list_supports_the_unread_filter(client):
    fake_client = _install(has_permission=True, table_responses={"notifications": FakeResponse(data=[_notification_row()], count=1)})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications", params={"is_read": "false"})
    assert response.status_code == 200
    assert response.json()["items"][0]["is_read"] is False
    assert "notifications" in fake_client.table_calls


# ---- GET /notifications/{id} ----


def test_get_by_id_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/{NOTIFICATION_ID}")
    assert response.status_code == 401


def test_get_by_id_returns_the_notification(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/{NOTIFICATION_ID}")
    assert response.status_code == 200
    assert response.json()["id"] == NOTIFICATION_ID


def test_get_by_id_not_found_is_404(client):
    """Models both "doesn't exist" and "belongs to a different
    recipient/workspace" — get_for_workspace 404s either way, same as
    every other *_for_workspace getter (workspace isolation, §9)."""
    _install(has_permission=True, table_responses={"notifications": FakeResponse(data=None)})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/{uuid4()}")
    assert response.status_code == 404


# ---- PATCH /notifications/{id} ----


def test_mark_read_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/{NOTIFICATION_ID}", json={"is_read": True})
    assert response.status_code == 401


def test_mark_read_denied_without_permission(client):
    _install(has_permission=False)
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/{NOTIFICATION_ID}", json={"is_read": True})
    assert response.status_code == 403


def test_mark_read_updates_is_read(client):
    fake_client = _install(
        has_permission=True,
        table_responses={"notifications": FakeResponse(data=[_notification_row(is_read=True, read_at="2026-01-02T00:00:00Z")])},
    )
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/{NOTIFICATION_ID}", json={"is_read": True})
    assert response.status_code == 200
    assert response.json()["is_read"] is True
    assert "notifications" in fake_client.table_calls


def test_mark_read_ignores_a_client_supplied_recipient_or_content_field(client):
    """NotificationMarkReadUpdate only declares `is_read` — extra body
    fields (an attempt to change the recipient, title, or type) are
    simply dropped by pydantic before reaching the service, mirroring
    CallCreate's actor-spoofing test. The `prevent_notification_content_edit`
    trigger (000011_notifications_audit.sql) would reject any of those
    columns changing anyway, even from a service-role write."""
    fake_client = _install(has_permission=True)
    response = client.patch(
        f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/{NOTIFICATION_ID}",
        json={"is_read": True, "recipient_member_id": str(uuid4()), "title": "Hacked", "type": "system"},
    )
    assert response.status_code == 200
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_mark_read_not_found_is_404(client):
    _install(has_permission=True, table_responses={"notifications": FakeResponse(data=[])})
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/{uuid4()}", json={"is_read": True})
    assert response.status_code == 404


# ---- POST /notifications/mark-all-read ----


def test_mark_all_read_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/mark-all-read")
    assert response.status_code == 401


def test_mark_all_read_denied_without_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/mark-all-read")
    assert response.status_code == 403


def test_mark_all_read_returns_the_updated_count(client):
    fake_client = _install(
        has_permission=True,
        table_responses={"notifications": FakeResponse(data=[_notification_row(), _notification_row(id=str(uuid4()))])},
    )
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/notifications/mark-all-read")
    assert response.status_code == 200
    assert response.json()["updated"] == 2
    assert "notifications" in fake_client.table_calls
