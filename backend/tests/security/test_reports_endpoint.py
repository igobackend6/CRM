from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
MEMBER_ID = str(uuid4())
STATUS_ID = str(uuid4())


def _default_tables():
    return {
        "lead_statuses": FakeResponse(data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]),
        "lead_sources": FakeResponse(data=[]),
        "call_outcomes": FakeResponse(data=[]),
        "leads": FakeResponse(data=[], count=0),
        "follow_ups": FakeResponse(data=[], count=0),
        "calls": FakeResponse(data=[], count=0),
        "workspace_members": FakeResponse(data=[]),
    }


def _install(*, is_member: bool, has_reports_permission: bool = False, table_responses=None):
    fake_client = FakeSupabaseClient(
        table_responses=table_responses or _default_tables(),
        rpc_responses={
            "is_workspace_member": is_member,
            "has_permission": has_reports_permission,
            "current_member_id": MEMBER_ID,
            "report_call_duration_stats": [{"total_talk_seconds": 0, "average_call_seconds": 0.0}],
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


# ---- GET /reports/personal — plain membership, like the dashboard ----


def test_personal_report_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/personal")
    assert response.status_code == 401


def test_personal_report_denied_for_a_non_member(client):
    _install(is_member=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/personal")
    assert response.status_code == 403


def test_personal_report_available_without_reports_read_permission(client):
    """A team_mate never has `reports.read` (000013_reference_data.sql)
    but must still see their own personal report — same reasoning as
    the dashboard's plain-membership gate."""
    _install(is_member=True, has_reports_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/personal")
    assert response.status_code == 200
    body = response.json()
    assert set(body.keys()) == {"range", "since", "until", "calls", "follow_ups", "leads", "pipeline"}


def test_personal_report_rejects_an_invalid_range(client):
    _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/personal", params={"range": "last_year"})
    assert response.status_code == 422


def test_personal_report_workspace_id_is_taken_from_the_path(client):
    fake_client = _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/personal")
    assert response.status_code == 200
    assert ("is_workspace_member", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


# ---- GET /reports/team — requires reports.read ----


def test_team_report_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/team")
    assert response.status_code == 401


def test_team_report_denied_for_a_member_without_reports_read(client):
    """A team_mate is an active member but never has `reports.read` —
    must be denied the workspace-wide team view (§"Team Reports":
    "enforce them consistently")."""
    _install(is_member=True, has_reports_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/team")
    assert response.status_code == 403


def test_team_report_available_to_a_manager(client):
    _install(is_member=True, has_reports_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/team")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0
    assert body["totals"]["conversion_rate"] == 0.0


def test_team_report_rejects_an_excessive_page_size(client):
    _install(is_member=True, has_reports_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/team", params={"limit": 1000})
    assert response.status_code == 422


def test_team_report_rejects_a_negative_offset(client):
    _install(is_member=True, has_reports_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/team", params={"offset": -1})
    assert response.status_code == 422


def test_team_report_default_pagination_envelope(client):
    _install(is_member=True, has_reports_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/team")
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 20
    assert body["offset"] == 0


# ---- GET /reports/pipeline — requires reports.read ----


def test_pipeline_report_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/pipeline")
    assert response.status_code == 401


def test_pipeline_report_denied_for_a_member_without_reports_read(client):
    _install(is_member=True, has_reports_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/pipeline")
    assert response.status_code == 403


def test_pipeline_report_available_to_an_admin(client):
    _install(is_member=True, has_reports_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/pipeline")
    assert response.status_code == 200
    body = response.json()
    # `_default_tables()` configures one lead_status row (so non-pipeline
    # tests reusing it still resolve a default status) — its count is 0,
    # same as everything else, not an empty list.
    assert body["leads_by_status"] == [{"status": body["leads_by_status"][0]["status"], "count": 0, "percentage": 0.0}]
    assert body["priority_distribution"][0]["percentage"] == 0.0


def test_pipeline_report_rejects_an_invalid_range(client):
    _install(is_member=True, has_reports_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/pipeline", params={"range": "whenever"})
    assert response.status_code == 422


def test_pipeline_report_workspace_id_is_taken_from_the_path_not_the_client(client):
    """Never trusts a client-supplied workspace identity — the only
    workspace_id in play is the one already validated from the URL path
    by require_permission."""
    fake_client = _install(is_member=True, has_reports_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/pipeline")
    assert response.status_code == 200
    assert ("has_permission", {"p_workspace_id": WORKSPACE_ID, "p_permission_code": "reports.read"}) in fake_client.rpc_calls


# ---- custom range validation (shared logic, exercised once per endpoint family) ----


def test_personal_report_custom_range_without_bounds_is_a_422():
    """resolve_report_range raises ValidationError (a 4xx app exception,
    not a 500) when range=custom is missing since/until — FastAPI's
    exception handler maps ValidationError to 422, same as every other
    service-level validation error in this codebase."""
    client_ = TestClient(app)
    _install(is_member=True)
    response = client_.get(f"/api/v1/workspaces/{WORKSPACE_ID}/reports/personal", params={"range": "custom"})
    assert response.status_code == 422
