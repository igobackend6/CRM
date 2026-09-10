from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
TEMPLATE_ID = str(uuid4())
MEMBER_ID = str(uuid4())


def _row(**overrides):
    row = {
        "id": TEMPLATE_ID,
        "workspace_id": WORKSPACE_ID,
        "name": "Follow-up",
        "body": "Hello {{name}}, checking in.",
        "created_by_member_id": MEMBER_ID,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    fake_client = FakeSupabaseClient(
        table_responses=table_responses or {"message_templates": FakeResponse(data=[_row()])},
        rpc_responses={"has_permission": has_permission, "is_workspace_member": is_member, "current_member_id": MEMBER_ID},
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


# ---- GET /message-templates (plain membership, no specific permission) ----


def test_list_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates")
    assert response.status_code == 401


def test_list_denied_for_a_non_member(client):
    _install(has_permission=True, is_member=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates")
    assert response.status_code == 403


def test_list_succeeds_for_any_workspace_member(client):
    _install(has_permission=False)  # no templates.manage — read still works
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates")
    assert response.status_code == 200
    assert response.json()[0]["name"] == "Follow-up"


# ---- POST /message-templates ----


def test_create_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates", json={"name": "New", "body": "Hi {{name}}"})
    assert response.status_code == 401


def test_create_denied_without_templates_manage_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates", json={"name": "New", "body": "Hi {{name}}"})
    assert response.status_code == 403


def test_create_succeeds(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates", json={"name": "Follow-up", "body": "Hi {{name}}"})
    assert response.status_code == 201
    assert response.json()["name"] == "Follow-up"


def test_create_rejects_an_empty_body(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates", json={"name": "New", "body": ""})
    assert response.status_code == 422


def test_create_rejects_a_duplicate_name_as_409(client):
    from postgrest.exceptions import APIError

    class _ConflictClient(FakeSupabaseClient):
        def table(self, name: str):
            builder = super().table(name)

            def _execute():
                raise APIError({"code": "23505", "message": "duplicate key"})

            builder.execute = _execute
            return builder

    fake_client = _ConflictClient(rpc_responses={"has_permission": True, "is_workspace_member": True, "current_member_id": MEMBER_ID})
    app.dependency_overrides[deps.get_current_user] = lambda: AuthenticatedUser(
        id=uuid4(), email="rep@example.com", access_token="fake-token"
    )
    app.dependency_overrides[deps.get_user_client] = lambda: fake_client
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates", json={"name": "Follow-up", "body": "Hi"})
    assert response.status_code == 409


# ---- PATCH /message-templates/{id} ----


def test_update_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates/{TEMPLATE_ID}", json={"name": "Renamed"})
    assert response.status_code == 401


def test_update_denied_without_templates_manage_permission(client):
    _install(has_permission=False)
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates/{TEMPLATE_ID}", json={"name": "Renamed"})
    assert response.status_code == 403


def test_update_succeeds(client):
    _install(has_permission=True, table_responses={"message_templates": FakeResponse(data=[_row(name="Renamed")])})
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates/{TEMPLATE_ID}", json={"name": "Renamed"})
    assert response.status_code == 200
    assert response.json()["name"] == "Renamed"


def test_update_404s_for_a_template_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={"message_templates": FakeResponse(data=[])})
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates/{TEMPLATE_ID}", json={"name": "Renamed"})
    assert response.status_code == 404


# ---- DELETE /message-templates/{id} ----


def test_delete_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates/{TEMPLATE_ID}")
    assert response.status_code == 401


def test_delete_denied_without_templates_manage_permission(client):
    _install(has_permission=False)
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates/{TEMPLATE_ID}")
    assert response.status_code == 403


def test_delete_succeeds(client):
    _install(has_permission=True)
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates/{TEMPLATE_ID}")
    assert response.status_code == 204


def test_delete_404s_for_a_template_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={"message_templates": FakeResponse(data=[])})
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/message-templates/{TEMPLATE_ID}")
    assert response.status_code == 404
