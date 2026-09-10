from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
LEAD_ID = str(uuid4())
STATUS_ID = str(uuid4())
LOST_STATUS_ID = str(uuid4())
MEMBER_ID = str(uuid4())


def _lead_row():
    return {
        "id": LEAD_ID,
        "workspace_id": WORKSPACE_ID,
        "name": "Acme Corp",
        "phone": "+15551234567",
        "email": "acme@example.com",
        "priority": "medium",
        "status_id": STATUS_ID,
        "source_id": None,
        "assigned_member_id": MEMBER_ID,
        "is_customer": False,
        "updated_at": "2025-01-01T00:00:00Z",
    }


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "leads": FakeResponse(data=[_lead_row()], count=1),
            "lead_statuses": FakeResponse(
                data=[
                    {"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True},
                    {"id": LOST_STATUS_ID, "name": "Lost", "code": "lost", "sort_order": 90, "stage": "closed_lost", "is_default": False},
                ]
            ),
            "lead_sources": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
            "follow_ups": FakeResponse(data=[]),
        },
        rpc_responses={"has_permission": has_permission, "is_workspace_member": is_member},
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


def test_rechurn_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn")
    assert response.status_code == 401


def test_rechurn_denied_without_leads_read_permission(client):
    """Same gate as `GET /leads`/`GET /pipeline` — leads.read, not a new
    permission."""
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn")
    assert response.status_code == 403


def test_rechurn_succeeds_for_a_permitted_member(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Acme Corp"
    assert body["items"][0]["assigned_member"]["full_name"] == "Rep One"
    assert body["items"][0]["next_follow_up"] is None


def test_rechurn_accepts_the_inactive_segment(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn", params={"segment": "inactive"})
    assert response.status_code == 200


def test_rechurn_accepts_the_lost_segment(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn", params={"segment": "lost"})
    assert response.status_code == 200


def test_rechurn_rejects_an_unknown_segment(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn", params={"segment": "won"})
    assert response.status_code == 422


def test_rechurn_accepts_a_custom_inactive_days(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn", params={"inactive_days": 90})
    assert response.status_code == 200


def test_rechurn_rejects_a_non_positive_inactive_days(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn", params={"inactive_days": 0})
    assert response.status_code == 422


def test_rechurn_rejects_a_cross_workspace_status_id(client):
    """Never trusts a client-supplied filter id — validated against THIS
    workspace's own lead_statuses before it reaches the query (same rule
    `GET /leads` already enforces for `status_id`)."""
    _install(has_permission=True, table_responses={"lead_statuses": FakeResponse(data=[]), "leads": FakeResponse(data=[], count=0)})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn", params={"status_id": str(uuid4())})
    assert response.status_code == 422


def test_rechurn_rejects_a_limit_above_the_cap(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn", params={"limit": 500})
    assert response.status_code == 422


def test_rechurn_workspace_id_is_taken_from_the_path_not_the_client(client):
    """Never trusts a client-supplied workspace identity — the only
    workspace_id in play is the one already validated by
    require_permission from the URL path."""
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn")
    assert response.status_code == 200
    assert ("has_permission", {"p_workspace_id": WORKSPACE_ID, "p_permission_code": "leads.read"}) in fake_client.rpc_calls


def test_rechurn_on_an_empty_workspace_returns_an_empty_page(client):
    _install(has_permission=True, table_responses={"leads": FakeResponse(data=[], count=0), "lead_statuses": FakeResponse(data=[]), "lead_sources": FakeResponse(data=[]), "workspace_members": FakeResponse(data=[]), "follow_ups": FakeResponse(data=[])})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/rechurn")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0
