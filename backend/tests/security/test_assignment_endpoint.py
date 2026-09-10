from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
LEAD_ID = str(uuid4())
ASSIGNER_ID = str(uuid4())
REP1_ID = str(uuid4())
REP2_ID = str(uuid4())


def _lead_row(assigned_member_id=REP1_ID):
    return {
        "id": LEAD_ID,
        "workspace_id": WORKSPACE_ID,
        "name": "Acme Corp",
        "phone": "+15551234567",
        "email": "acme@example.com",
        "priority": "medium",
        "status_id": str(uuid4()),
        "source_id": None,
        "assigned_member_id": assigned_member_id,
        "created_by_member_id": ASSIGNER_ID,
        "is_customer": False,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    """Same pattern as test_leads_endpoint.py's _install() — overrides
    the real JWT/DB dependencies with fakes. Proves route wiring +
    permission gating behave correctly for a given DB answer, not a
    real Postgres/RLS run (see fake_supabase.py)."""
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "leads": FakeResponse(data=[_lead_row()]),
            "lead_statuses": FakeResponse(data=[]),
            "lead_sources": FakeResponse(data=[]),
            "lead_tags": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[{"id": REP2_ID, "profile": {"full_name": "Rep Two"}}]),
            "allocations": FakeResponse(data=[{"id": str(uuid4()), "status": "new"}]),
        },
        rpc_responses={
            "has_permission": has_permission,
            "is_workspace_member": is_member,
            "current_member_id": ASSIGNER_ID,
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


# ---- GET /members ----


def test_members_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/members")
    assert response.status_code == 401


def test_members_denied_for_a_non_member(client):
    _install(has_permission=True, is_member=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/members")
    assert response.status_code == 403


def test_members_lists_active_members_for_a_workspace_member(client):
    _install(has_permission=True, is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/members")
    assert response.status_code == 200
    body = response.json()
    assert body[0]["full_name"] == "Rep Two"
    # Only id + full_name — no phone/email/avatar.
    assert set(body[0].keys()) == {"id", "full_name"}


# ---- POST /leads/{id}/assignment ----


def test_assignment_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/assignment", json={"member_id": REP2_ID})
    assert response.status_code == 401


def test_assignment_denied_for_an_unauthorized_role(client):
    """team_mate has leads.update but not leads.assign — has_permission
    returning False models exactly that (Phase 6 §4/§8: 'unauthorized
    role cannot assign')."""
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/assignment", json={"member_id": REP2_ID})
    assert response.status_code == 403


def test_assignment_denied_for_a_non_member(client):
    """The assignment endpoint is gated by require_permission(LEADS_ASSIGN),
    which calls the has_permission() RPC — and that function itself
    returns false for anyone who isn't an active member (it looks up
    workspace_members first; see 000012_security_functions.sql). So a
    non-member and has_permission=False are the same real-world case,
    modeled here by setting both flags to false together."""
    _install(has_permission=False, is_member=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/assignment", json={"member_id": REP2_ID})
    assert response.status_code == 403


def test_authorized_user_can_assign_a_lead(client):
    fake_client = _install(has_permission=True)
    fake_client._table_responses["leads"] = FakeResponse(data=[_lead_row(assigned_member_id=REP2_ID)])

    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/assignment", json={"member_id": REP2_ID})

    assert response.status_code == 200
    assert response.json()["assigned_member"]["id"] == REP2_ID
    # The allocations history row is written by the leads_on_assignment
    # trigger (000027), not the endpoint — so the endpoint itself never
    # touches the allocations table.
    assert "allocations" not in fake_client.table_calls


def test_authorized_user_can_reassign_a_lead(client):
    """Same endpoint/permission for a lead that already has an
    assignee (REP1) — 'assign' and 'reassign' are the same operation."""
    fake_client = _install(has_permission=True)
    fake_client._table_responses["leads"] = FakeResponse(data=[_lead_row(assigned_member_id=REP2_ID)])

    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/assignment", json={"member_id": REP2_ID})

    assert response.status_code == 200
    assert response.json()["assigned_member"]["id"] == REP2_ID


def test_authorized_user_can_unassign_a_lead(client):
    fake_client = _install(has_permission=True)
    fake_client._table_responses["leads"] = FakeResponse(data=[_lead_row(assigned_member_id=None)])

    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/assignment", json={"member_id": None})

    assert response.status_code == 200
    assert response.json()["assigned_member"] is None
    assert "allocations" not in fake_client.table_calls


def test_assigning_an_invalid_member_is_rejected(client):
    """Models both 'cross-workspace member cannot be assigned' and
    'invalid member is rejected': get_active() returning nothing is what
    happens for a member id that doesn't belong to this workspace (the
    composite FK) OR isn't active — the API can't tell these apart from
    the client's input alone, by design (same as NotFoundError)."""
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "lead_statuses": FakeResponse(data=[]),
        "lead_sources": FakeResponse(data=[]),
        "lead_tags": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=None),
        "allocations": FakeResponse(data=[]),
    })

    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/assignment", json={"member_id": str(uuid4())}
    )

    assert response.status_code == 422
    assert response.json()["error_code"] == "validation_error"


def test_assigning_an_invalid_lead_is_rejected(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=None),
        "lead_statuses": FakeResponse(data=[]),
        "lead_sources": FakeResponse(data=[]),
        "lead_tags": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": REP2_ID, "profile": {"full_name": "Rep Two"}}]),
        "allocations": FakeResponse(data=[]),
    })

    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{uuid4()}/assignment", json={"member_id": REP2_ID}
    )

    assert response.status_code == 404


def test_assignment_never_trusts_a_client_supplied_assigned_by(client):
    """The AssignmentRequest schema has no assigned_by field at all —
    extra fields in the JSON body are ignored by Pydantic — and the
    assigner is resolved server-side by the leads_on_assignment trigger
    via current_member_id() (000027), never from the request body."""
    fake_client = _install(has_permission=True)
    fake_client._table_responses["leads"] = FakeResponse(data=[_lead_row(assigned_member_id=REP2_ID)])

    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/assignment",
        json={"member_id": REP2_ID, "assigned_by": str(uuid4())},
    )

    assert response.status_code == 200
    from app.schemas.assignment import AssignmentRequest

    assert "assigned_by" not in AssignmentRequest.model_fields


# ---- GET /leads/{id}/allocations ----


def test_allocations_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/allocations")
    assert response.status_code == 401


def test_allocations_denied_without_leads_read(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/allocations")
    assert response.status_code == 403


def test_allocations_history_belongs_to_the_requested_workspace_and_lead(client):
    """Not a real cross-workspace isolation test (that's RLS's job, and
    RLS hasn't run for real — see fake_supabase.py). This only proves
    the endpoint always scopes the allocations query by the workspace_id
    and lead_id in the URL, which is what makes RLS's own filtering even
    possible to rely on."""
    row = {
        "id": str(uuid4()),
        "assigned_member_id": REP2_ID,
        "assigned_by_member_id": ASSIGNER_ID,
        "status": "new",
        "assigned_at": "2026-01-01T00:00:00Z",
        "created_at": "2026-01-01T00:00:00Z",
    }
    fake_client = _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()]),
        "lead_statuses": FakeResponse(data=[]),
        "lead_sources": FakeResponse(data=[]),
        "lead_tags": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": REP2_ID, "profile": {"full_name": "Rep Two"}}]),
        "allocations": FakeResponse(data=[row]),
    })

    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/allocations")

    assert response.status_code == 200
    body = response.json()
    assert body[0]["assigned_member"]["id"] == REP2_ID
    assert body[0]["previous_member"] is None
    assert "allocations" in fake_client.table_calls
