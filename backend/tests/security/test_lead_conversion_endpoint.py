from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
LEAD_ID = str(uuid4())
ACTOR_ID = str(uuid4())
ASSIGNEE_ID = str(uuid4())


def _lead_row(*, is_customer=False, assigned_member_id=ASSIGNEE_ID):
    """See tests/unit/test_lead_conversion_service.py's `_client()` for
    why every test here configures a single, consistent "before" row
    rather than trying to distinguish pre-/post-conversion state — the
    fake shares one FakeResponse per table name across every call."""
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
        "created_by_member_id": ACTOR_ID,
        "is_customer": is_customer,
        "converted_at": None,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    """Same pattern as test_assignment_endpoint.py's _install()."""
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "leads": FakeResponse(data=[_lead_row()]),
            "lead_statuses": FakeResponse(data=[]),
            "lead_sources": FakeResponse(data=[]),
            "lead_tags": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[{"id": ASSIGNEE_ID, "profile": {"full_name": "Rep One"}}]),
            "interactions": FakeResponse(data=[{"id": str(uuid4()), "type": "status_change", "payload": {}}]),
        },
        rpc_responses={
            "has_permission": has_permission,
            "is_workspace_member": is_member,
            "current_member_id": ACTOR_ID,
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


def _convert(client, workspace_id=WORKSPACE_ID, lead_id=LEAD_ID):
    return client.post(f"/api/v1/workspaces/{workspace_id}/leads/{lead_id}/convert")


def test_convert_requires_authentication(client):
    app.dependency_overrides.clear()
    response = _convert(client)
    assert response.status_code == 401


def test_convert_denied_without_leads_update_permission(client):
    """A role without leads.update (e.g. a plain team_mate, per the RBAC
    catalog) cannot convert a lead — same permission update_lead/
    change_lead_status already require."""
    _install(has_permission=False)
    response = _convert(client)
    assert response.status_code == 403


def test_convert_denied_for_a_non_member(client):
    _install(has_permission=False, is_member=False)
    response = _convert(client)
    assert response.status_code == 403


def test_convert_denied_for_a_lead_outside_the_caller_workspace(client):
    """Not a real cross-workspace isolation test (that's RLS's job — see
    fake_supabase.py); this proves the endpoint always scopes the lookup
    by the workspace_id in the URL, so a lead RLS hides (because it
    belongs to a different workspace) 404s exactly like a missing one."""
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=None),
        "lead_statuses": FakeResponse(data=[]),
        "lead_sources": FakeResponse(data=[]),
        "lead_tags": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[]),
        "interactions": FakeResponse(data=[]),
    })
    response = _convert(client)
    assert response.status_code == 404


def test_authorized_user_can_convert_a_lead_to_a_customer(client):
    fake_client = _install(has_permission=True)
    response = _convert(client)

    assert response.status_code == 200
    assert response.json()["id"] == LEAD_ID
    assert "interactions" in fake_client.table_calls


def test_converting_an_already_converted_lead_returns_a_conflict(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row(is_customer=True)]),
        "lead_statuses": FakeResponse(data=[]),
        "lead_sources": FakeResponse(data=[]),
        "lead_tags": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": ASSIGNEE_ID, "profile": {"full_name": "Rep One"}}]),
        "interactions": FakeResponse(data=[]),
    })

    response = _convert(client)

    assert response.status_code == 409
    assert response.json()["error_code"] == "conflict"


def test_convert_never_trusts_a_client_supplied_actor(client):
    """No request body at all is accepted by this route — there is
    nothing a client could supply to override the server-derived actor."""
    fake_client = _install(has_permission=True)

    response = _convert(client)

    assert response.status_code == 200
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_dashboard_compatible_conversion_flow_is_idempotent_safe(client):
    """First conversion succeeds; the SAME lead converted again (now
    is_customer=true) is rejected rather than double-counted — the
    guarantee Phase 17's converted_leads_in_range/conversion_rate metrics
    depend on (each real lead contributes at most one converted_at
    stamp)."""
    _install(has_permission=True)
    first = _convert(client)
    assert first.status_code == 200

    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row(is_customer=True)]),
        "lead_statuses": FakeResponse(data=[]),
        "lead_sources": FakeResponse(data=[]),
        "lead_tags": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": ASSIGNEE_ID, "profile": {"full_name": "Rep One"}}]),
        "interactions": FakeResponse(data=[]),
    })
    second = _convert(client)
    assert second.status_code == 409
