from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
LEAD_ID = str(uuid4())
CALL_ID = str(uuid4())
AGENT_ID = str(uuid4())
OUTCOME_ID = str(uuid4())


def _lead_row():
    return {"id": LEAD_ID, "workspace_id": WORKSPACE_ID, "name": "Acme Corp"}


def _call_row(**overrides):
    row = {
        "id": CALL_ID,
        "workspace_id": WORKSPACE_ID,
        "lead_id": LEAD_ID,
        "agent_member_id": AGENT_ID,
        "direction": "outbound",
        "state": "ENDED",
        "outcome_id": None,
        "started_at": "2026-01-01T00:00:00Z",
        "connected_at": None,
        "ended_at": None,
        "duration_seconds": None,
        "notes": None,
        "created_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    """Same pattern as test_followups_endpoint.py's _install()."""
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "leads": FakeResponse(data=[_lead_row()]),
            "calls": FakeResponse(data=[_call_row()], count=1),
            "workspace_members": FakeResponse(data=[{"id": AGENT_ID, "profile": {"full_name": "Agent Smith"}}]),
            "call_outcomes": FakeResponse(data=[{"id": OUTCOME_ID, "name": "Connected", "code": "connected", "is_positive": True, "is_default": False}]),
        },
        rpc_responses={
            "has_permission": has_permission,
            "is_workspace_member": is_member,
            "current_member_id": AGENT_ID,
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


# ---- GET /calls ----


def test_list_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls")
    assert response.status_code == 401


def test_list_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls")
    assert response.status_code == 403


def test_list_returns_workspace_scoped_calls(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls")
    assert response.status_code == 200
    body = response.json()
    assert body["items"][0]["lead"]["name"] == "Acme Corp"
    assert body["total"] == 1
    assert "calls" in fake_client.table_calls


def test_list_supports_pagination_query_params(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls", params={"limit": 5, "offset": 10})
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 5
    assert body["offset"] == 10


# ---- GET /calls/{id} ----


def test_get_by_id_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}")
    assert response.status_code == 401


def test_get_by_id_returns_the_call(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{CALL_ID}")
    assert response.status_code == 200
    assert response.json()["id"] == CALL_ID


def test_get_by_id_not_found_is_404(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "calls": FakeResponse(data=None),
        "workspace_members": FakeResponse(data=[]),
        "call_outcomes": FakeResponse(data=[]),
    })
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/calls/{uuid4()}")
    assert response.status_code == 404


# ---- POST /calls ----


def test_create_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls", json={"lead_id": LEAD_ID, "direction": "outbound"})
    assert response.status_code == 401


def test_create_denied_for_unauthorized_role(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls", json={"lead_id": LEAD_ID, "direction": "outbound"})
    assert response.status_code == 403


def test_create_succeeds_for_an_authorized_user(client):
    fake_client = _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/calls",
        json={"lead_id": LEAD_ID, "direction": "outbound", "notes": "Discussed pricing"},
    )
    assert response.status_code == 201
    assert response.json()["lead"]["id"] == LEAD_ID
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_create_ignores_a_client_supplied_actor(client):
    """§9: CallCreate has no agent/actor field at all — even if a client
    sends one, pydantic's default `extra` behavior on request bodies
    (fields not declared on CallCreate are simply dropped) means it can
    never reach the service; current_member_id() is the only source."""
    fake_client = _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/calls",
        json={"lead_id": LEAD_ID, "direction": "outbound", "agent_member_id": str(uuid4()), "workspace_id": str(uuid4())},
    )
    assert response.status_code == 201
    assert response.json()["agent_member"]["id"] == AGENT_ID
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_create_rejects_a_lead_from_another_workspace(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=None),
        "calls": FakeResponse(data=[_call_row()]),
        "workspace_members": FakeResponse(data=[]),
        "call_outcomes": FakeResponse(data=[]),
    })
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls", json={"lead_id": str(uuid4()), "direction": "outbound"})
    assert response.status_code == 404


def test_create_rejects_an_invalid_outcome(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "calls": FakeResponse(data=[_call_row()]),
        "workspace_members": FakeResponse(data=[]),
        "call_outcomes": FakeResponse(data=None),
    })
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/calls",
        json={"lead_id": LEAD_ID, "direction": "outbound", "outcome_id": str(uuid4())},
    )
    assert response.status_code == 422
    assert response.json()["error_code"] == "validation_error"


def test_create_rejects_an_invalid_direction(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/calls", json={"lead_id": LEAD_ID, "direction": "sideways"})
    assert response.status_code == 422


# ---- GET /leads/{lead_id}/calls ----


def test_lead_calls_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/calls")
    assert response.status_code == 401


def test_lead_calls_denied_without_leads_read(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/calls")
    assert response.status_code == 403


def test_lead_calls_scoped_to_the_requested_lead(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/calls")
    assert response.status_code == 200
    body = response.json()
    assert body[0]["lead"]["id"] == LEAD_ID
    assert "calls" in fake_client.table_calls


def test_lead_calls_rejects_a_lead_that_is_not_visible_in_this_workspace(client):
    """Models workspace isolation: a lead id belonging to another
    workspace looks identical to a missing one under RLS —
    get_for_workspace 404s either way."""
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=None),
        "calls": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[]),
        "call_outcomes": FakeResponse(data=[]),
    })
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{uuid4()}/calls")
    assert response.status_code == 404


# ---- GET /call-outcomes ----


def test_list_outcomes_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/call-outcomes")
    assert response.status_code == 401


def test_list_outcomes_returns_the_workspace_catalogue(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/call-outcomes")
    assert response.status_code == 200
    assert response.json()[0]["code"] == "connected"
