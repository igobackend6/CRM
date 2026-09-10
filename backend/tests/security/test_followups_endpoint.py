from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
LEAD_ID = str(uuid4())
FOLLOW_UP_ID = str(uuid4())
CREATOR_ID = str(uuid4())
REP1_ID = str(uuid4())
REP2_ID = str(uuid4())


def _lead_row():
    return {"id": LEAD_ID, "workspace_id": WORKSPACE_ID, "name": "Acme Corp"}


def _follow_up_row(**overrides):
    row = {
        "id": FOLLOW_UP_ID,
        "workspace_id": WORKSPACE_ID,
        "lead_id": LEAD_ID,
        "assigned_member_id": REP1_ID,
        "created_by_member_id": CREATOR_ID,
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


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    """Same pattern as test_assignment_endpoint.py's _install()."""
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "leads": FakeResponse(data=[_lead_row()]),
            "follow_ups": FakeResponse(data=[_follow_up_row()], count=1),
            "workspace_members": FakeResponse(data=[{"id": REP2_ID, "profile": {"full_name": "Rep Two"}}]),
        },
        rpc_responses={
            "has_permission": has_permission,
            "is_workspace_member": is_member,
            "current_member_id": CREATOR_ID,
        },
    )
    app.dependency_overrides[deps.get_current_user] = lambda: AuthenticatedUser(
        id=uuid4(), email="manager@example.com", access_token="fake-token"
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


# ---- GET /follow-ups ----


def test_list_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups")
    assert response.status_code == 401


def test_list_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups")
    assert response.status_code == 403


def test_list_returns_workspace_scoped_follow_ups(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups")
    assert response.status_code == 200
    body = response.json()
    assert body["items"][0]["lead"]["name"] == "Acme Corp"
    assert body["total"] == 1
    assert "follow_ups" in fake_client.table_calls


def test_get_by_id_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{FOLLOW_UP_ID}")
    assert response.status_code == 401


def test_get_by_id_not_found_is_404(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "follow_ups": FakeResponse(data=None),
        "workspace_members": FakeResponse(data=[]),
    })
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{uuid4()}")
    assert response.status_code == 404


# ---- POST /follow-ups ----


def test_create_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups",
        json={"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call"},
    )
    assert response.status_code == 401


def test_create_denied_for_unauthorized_role(client):
    """team_mate without followups.create — has_permission=False models
    this (Phase 7 §11 'permission denial')."""
    _install(has_permission=False)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups",
        json={"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call"},
    )
    assert response.status_code == 403


def test_create_succeeds_for_an_authorized_user(client):
    fake_client = _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups",
        json={"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call", "notes": "Call to confirm budget"},
    )
    assert response.status_code == 201
    assert response.json()["lead"]["id"] == LEAD_ID
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_create_rejects_an_invalid_lead(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=None),
        "follow_ups": FakeResponse(data=[_follow_up_row()]),
        "workspace_members": FakeResponse(data=[]),
    })
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups",
        json={"lead_id": str(uuid4()), "due_at": "2026-02-01T09:00:00Z", "type": "call"},
    )
    assert response.status_code == 404


def test_create_rejects_an_invalid_or_cross_workspace_member(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "follow_ups": FakeResponse(data=[_follow_up_row()]),
        "workspace_members": FakeResponse(data=None),
    })
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups",
        json={"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "call", "assigned_member_id": str(uuid4())},
    )
    assert response.status_code == 422
    assert response.json()["error_code"] == "validation_error"


def test_create_rejects_an_invalid_type(client):
    _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups",
        json={"lead_id": LEAD_ID, "due_at": "2026-02-01T09:00:00Z", "type": "carrier_pigeon"},
    )
    assert response.status_code == 422


def test_create_never_trusts_a_client_supplied_creator(client):
    fake_client = _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups",
        json={
            "lead_id": LEAD_ID,
            "due_at": "2026-02-01T09:00:00Z",
            "type": "call",
            "created_by_member_id": str(uuid4()),
        },
    )
    assert response.status_code == 201
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


# ---- PATCH /follow-ups/{id} ----


def test_update_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{FOLLOW_UP_ID}", json={"notes": "x"})
    assert response.status_code == 401


def test_update_denied_for_unauthorized_role(client):
    _install(has_permission=False)
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{FOLLOW_UP_ID}", json={"notes": "x"})
    assert response.status_code == 403


def test_update_reschedules_the_due_date(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "follow_ups": FakeResponse(data=[_follow_up_row(due_at="2026-03-15T10:00:00Z")]),
        "workspace_members": FakeResponse(data=[]),
    })
    response = client.patch(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{FOLLOW_UP_ID}", json={"due_at": "2026-03-15T10:00:00Z"}
    )
    assert response.status_code == 200
    assert response.json()["due_at"].startswith("2026-03-15")


def test_update_marks_the_follow_up_completed(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "follow_ups": FakeResponse(data=[_follow_up_row(status="completed", completed_at="2026-01-10T00:00:00Z")]),
        "workspace_members": FakeResponse(data=[]),
    })
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{FOLLOW_UP_ID}", json={"status": "completed"})
    assert response.status_code == 200
    assert response.json()["status"] == "completed"
    assert response.json()["completed_at"] is not None


def test_update_cancels_the_follow_up(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "follow_ups": FakeResponse(data=[_follow_up_row(status="cancelled", cancelled_at="2026-01-10T00:00:00Z")]),
        "workspace_members": FakeResponse(data=[]),
    })
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{FOLLOW_UP_ID}", json={"status": "cancelled"})
    assert response.status_code == 200
    assert response.json()["status"] == "cancelled"
    assert response.json()["cancelled_at"] is not None


def test_update_rejects_an_invalid_follow_up_id(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "follow_ups": FakeResponse(data=None),
        "workspace_members": FakeResponse(data=[]),
    })
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{uuid4()}", json={"status": "completed"})
    assert response.status_code == 404


def test_update_rejects_an_invalid_assignee(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "follow_ups": FakeResponse(data=[_follow_up_row()]),
        "workspace_members": FakeResponse(data=None),
    })
    response = client.patch(
        f"/api/v1/workspaces/{WORKSPACE_ID}/follow-ups/{FOLLOW_UP_ID}", json={"assigned_member_id": str(uuid4())}
    )
    assert response.status_code == 422


# ---- GET /leads/{lead_id}/follow-ups ----


def test_lead_follow_ups_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/follow-ups")
    assert response.status_code == 401


def test_lead_follow_ups_denied_without_leads_read(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/follow-ups")
    assert response.status_code == 403


def test_lead_follow_ups_scoped_to_the_requested_lead(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/follow-ups")
    assert response.status_code == 200
    body = response.json()
    assert body[0]["lead"]["id"] == LEAD_ID
    assert "follow_ups" in fake_client.table_calls


def test_lead_follow_ups_rejects_a_lead_that_is_not_visible_in_this_workspace(client):
    """Models 'cross-workspace lead is rejected': a lead id that belongs
    to another workspace looks identical to a missing one under RLS —
    get_for_workspace 404s either way."""
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=None),
        "follow_ups": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[]),
    })
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{uuid4()}/follow-ups")
    assert response.status_code == 404
