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


def _install(*, is_member: bool, table_responses=None):
    """Dashboard routes gate on plain workspace membership, not a
    specific permission (see api/v1/dashboard.py's own docstring) — so
    `_install` takes `is_member` instead of the `has_permission`
    boolean the other endpoint test files use."""
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "lead_statuses": FakeResponse(data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]),
            "leads": FakeResponse(data=[], count=0),
            "follow_ups": FakeResponse(data=[], count=0),
            "calls": FakeResponse(data=[], count=0),
            "notifications": FakeResponse(data=[], count=0),
            "interactions": FakeResponse(data=[], count=0),
            "allocations": FakeResponse(data=[], count=0),
            "workspace_members": FakeResponse(data=[]),
        },
        rpc_responses={
            "is_workspace_member": is_member,
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


# ---- GET /dashboard/summary ----


def test_summary_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/summary")
    assert response.status_code == 401


def test_summary_denied_for_a_non_member(client):
    _install(is_member=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/summary")
    assert response.status_code == 403


def test_summary_available_to_any_workspace_member(client):
    """No `reports.read` (or any other specific permission) gate — a
    team_mate, who never has `reports.read`
    (000013_reference_data.sql), must still get their own dashboard."""
    fake_client = _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/summary")
    assert response.status_code == 200
    body = response.json()
    # Phase 11's original 9 fields, still present, plus Phase 17's
    # additive period-analytics fields (§"existing dashboard
    # compatibility").
    assert {
        "total_active_leads",
        "new_leads",
        "customers",
        "pending_follow_ups",
        "overdue_follow_ups",
        "completed_follow_ups",
        "total_calls",
        "todays_calls",
        "unread_notifications",
    } <= set(body.keys())
    assert {
        "range",
        "leads_created_in_range",
        "converted_leads_in_range",
        "conversion_rate",
        "calls_connected_in_range",
        "calls_completed_in_range",
        "completed_follow_ups_in_range",
        "leads_by_status",
        "team_productivity",
    } <= set(body.keys())
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_summary_on_an_empty_workspace_returns_all_zeros(client):
    _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/summary")
    assert response.status_code == 200
    body = response.json()
    ints = {k: v for k, v in body.items() if k not in {"range", "conversion_rate", "leads_by_status", "team_productivity"}}
    assert all(v == 0 for v in ints.values())
    assert body["range"] == "all"
    assert body["conversion_rate"] == 0.0
    # `_install`'s default fixture configures one lead_status row (so
    # non-dashboard tests reusing it still resolve a default status) —
    # its count is 0, same as everything else, not an empty list.
    assert body["leads_by_status"] == [{"status": body["leads_by_status"][0]["status"], "count": 0}]
    assert body["team_productivity"] == []


# ---- GET /dashboard/summary?range= (Phase 17) ----


def test_summary_accepts_a_range_query_param(client):
    fake_client = _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/summary", params={"range": "this_week"})
    assert response.status_code == 200
    assert response.json()["range"] == "this_week"
    # Never trusts a client-supplied workspace/member identity for this
    # either — range only ever narrows the date window of an
    # already-workspace-scoped, already-membership-checked query.
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_summary_rejects_an_unknown_range_value(client):
    _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/summary", params={"range": "last_year"})
    assert response.status_code == 422


def test_summary_default_range_is_all(client):
    _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/summary")
    assert response.status_code == 200
    assert response.json()["range"] == "all"


# ---- GET /dashboard/recent-activity ----


def test_recent_activity_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/recent-activity")
    assert response.status_code == 401


def test_recent_activity_denied_for_a_non_member(client):
    _install(is_member=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/recent-activity")
    assert response.status_code == 403


def test_recent_activity_returns_a_paginated_envelope(client):
    _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/recent-activity", params={"limit": 5, "offset": 0})
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0
    assert body["limit"] == 5
    assert body["offset"] == 0


def test_recent_activity_rejects_a_limit_above_the_cap(client):
    _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/recent-activity", params={"limit": 500})
    assert response.status_code == 422


def test_recent_activity_workspace_id_is_taken_from_the_path_not_the_client(client):
    """Never trusts a client-supplied workspace/member identity (§"Backend
    Rules") — the only workspace_id in play is the one already validated
    by require_workspace_member from the URL path; there is no request
    body or query param that could smuggle a different one in."""
    fake_client = _install(is_member=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/dashboard/recent-activity")
    assert response.status_code == 200
    assert ("is_workspace_member", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls
