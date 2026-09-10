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
        "created_by_member_id": MEMBER_ID,
        "is_customer": False,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    """Overrides the real JWT/DB dependencies with fakes, the same way
    FastAPI's dependency_overrides is meant to be used for testing. Only
    proves the route wiring + authorization gate behave correctly for a
    given DB answer — not a real Postgres/RLS run (see fake_supabase.py).
    """
    fake_client = FakeSupabaseClient(
        table_responses=table_responses
        or {
            "leads": FakeResponse(data=[_lead_row()], count=1),
            "lead_statuses": FakeResponse(
                data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
            ),
            "lead_sources": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
            "lead_tags": FakeResponse(data=[]),
        },
        rpc_responses={
            "has_permission": has_permission,
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


def test_leads_requires_authentication(client):
    app.dependency_overrides.clear()  # no override: exercise the real JWT dependency
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads")
    assert response.status_code == 401


def test_list_leads_denied_without_leads_read_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads")
    assert response.status_code == 403


def test_list_leads_succeeds_for_a_permitted_member(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "Acme Corp"
    assert body["items"][0]["assigned_member"]["full_name"] == "Rep One"


# ---- Phase 14: advanced search & filters ----


def test_list_leads_with_every_filter_combined_succeeds_and_preserves_pagination(client):
    """Individual filters + pagination, combined in one request — a
    permitted member's request should still 200 with every filter this
    workspace's own reference data actually has, and still echo back the
    limit/offset it was asked for (§"pagination preserved")."""
    tag_id = str(uuid4())
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=[_lead_row()], count=1),
            "lead_statuses": FakeResponse(
                data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
            ),
            "lead_sources": FakeResponse(data=[{"id": str(uuid4()), "name": "Website", "code": "website", "is_default": False}]),
            "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
            "tags": FakeResponse(data=[{"id": tag_id, "name": "VIP", "color": None}]),
            "lead_tags": FakeResponse(data=[{"lead_id": LEAD_ID, "tag_id": tag_id}]),
        },
    )
    source_id = str(uuid4())

    response = client.get(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads",
        params={
            "search": "acme",
            "status_id": STATUS_ID,
            "assigned_member_id": MEMBER_ID,
            "priority": "medium",
            "is_customer": "false",
            "created_from": "2026-01-01T00:00:00Z",
            "created_to": "2026-12-31T00:00:00Z",
            "tag_id": tag_id,
            "limit": 10,
            "offset": 0,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 10
    assert body["offset"] == 0
    assert body["total"] == 1


def test_list_leads_rejects_a_status_id_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={"lead_statuses": FakeResponse(data=[])})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads", params={"status_id": str(uuid4())})
    assert response.status_code == 422


def test_list_leads_rejects_a_source_id_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={"lead_sources": FakeResponse(data=[])})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads", params={"source_id": str(uuid4())})
    assert response.status_code == 422


def test_list_leads_rejects_an_assigned_member_id_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={"workspace_members": FakeResponse(data=[])})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads", params={"assigned_member_id": str(uuid4())})
    assert response.status_code == 422


def test_list_leads_rejects_a_tag_id_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={"tags": FakeResponse(data=[])})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads", params={"tag_id": str(uuid4())})
    assert response.status_code == 422


def test_list_leads_rejects_an_invalid_priority(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads", params={"priority": "urgent-ish"})
    assert response.status_code == 422


def test_list_leads_with_a_customer_filter_and_date_range_is_compatible_with_the_existing_endpoint(client):
    """Confirms Phase 14's new query params are additive — a Phase 5-style
    request with none of them set still 200s exactly as before, and a
    request using only the customer/date-range filters (no status/source/
    member/tag/priority) also 200s."""
    _install(has_permission=True)
    response = client.get(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads",
        params={"is_customer": "false", "created_from": "2026-01-01T00:00:00Z"},
    )
    assert response.status_code == 200


def test_get_lead_404s_for_a_lead_the_query_does_not_return():
    """Covers both "doesn't exist" and "hidden by workspace isolation /
    RLS" — see NotFoundError's docstring: deliberately the same response
    either way."""
    app_client = TestClient(app)
    _install(has_permission=True, table_responses={"leads": FakeResponse(data=None)})
    response = app_client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{uuid4()}")
    assert response.status_code == 404


def test_get_lead_with_an_invalid_uuid_is_a_422(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/not-a-uuid")
    assert response.status_code == 422


def test_create_lead_requires_leads_create_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads", json={"name": "New Co"})
    assert response.status_code == 403


def test_create_lead_happy_path(client):
    fake_client = _install(has_permission=True)
    fake_client._table_responses["leads"] = FakeResponse(data=[_lead_row()])

    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads", json={"name": "Acme Corp", "phone": "+15551234567"})

    assert response.status_code == 201
    assert response.json()["name"] == "Acme Corp"


def test_create_lead_missing_name_is_a_422_validation_error(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads", json={"phone": "+15551234567"})
    assert response.status_code == 422
    assert response.json()["error_code"] == "validation_error"


def test_create_lead_never_trusts_a_client_supplied_owner(client):
    """Phase 5 §9: assigned_member_id/created_by_member_id are not even
    accepted fields on the request schema — extra fields are ignored by
    FastAPI/Pydantic, so a spoofed value in the body has no effect."""
    fake_client = _install(has_permission=True)
    fake_client._table_responses["leads"] = FakeResponse(data=[_lead_row()])

    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads",
        json={"name": "Acme Corp", "assigned_member_id": "11111111-1111-1111-1111-111111111111"},
    )

    assert response.status_code == 201
    # The server always resolves ownership via current_member_id(), never
    # the request body — see LeadService.create_lead.
    assert ("current_member_id", {"p_workspace_id": WORKSPACE_ID}) in fake_client.rpc_calls


def test_delete_lead_requires_leads_delete_permission(client):
    _install(has_permission=False)
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}")
    assert response.status_code == 403


def test_delete_lead_happy_path_is_a_soft_delete(client):
    fake_client = _install(has_permission=True)
    fake_client._table_responses["leads"] = FakeResponse(data=[{**_lead_row(), "deleted_at": "2026-01-02T00:00:00Z"}])

    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}")

    assert response.status_code == 204


def test_pipeline_requires_leads_read_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/pipeline")
    assert response.status_code == 403


def test_pipeline_groups_leads_under_their_status_column(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()], count=1),
        "lead_statuses": FakeResponse(
            data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
        ),
        "lead_sources": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
        "lead_tags": FakeResponse(data=[]),
    })
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/pipeline")
    assert response.status_code == 200
    body = response.json()
    assert len(body["columns"]) == 1
    column = body["columns"][0]
    assert column["status"]["id"] == STATUS_ID
    assert column["leads"][0]["name"] == "Acme Corp"
    # Only the pipeline card fields are present — no tags/source/etc.
    assert set(column["leads"][0].keys()) == {"id", "name", "phone", "email", "priority", "status", "assigned_member", "updated_at"}


def test_pipeline_denied_for_a_workspace_the_caller_is_not_permitted_in(client):
    other_workspace = str(uuid4())
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{other_workspace}/pipeline")
    assert response.status_code == 403


def test_change_lead_status_requires_leads_update_permission(client):
    _install(has_permission=False)
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/status", json={"status_id": STATUS_ID})
    assert response.status_code == 403


def test_change_lead_status_happy_path(client):
    fake_client = _install(has_permission=True)
    fake_client._table_responses["leads"] = FakeResponse(data=[_lead_row()])

    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/status", json={"status_id": STATUS_ID})

    assert response.status_code == 200
    assert response.json()["status"]["id"] == STATUS_ID


def test_change_lead_status_rejects_a_status_id_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={
        "leads": FakeResponse(data=[_lead_row()], count=1),
        "lead_statuses": FakeResponse(data=[]),  # no status in this workspace matches
        "lead_sources": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
        "lead_tags": FakeResponse(data=[]),
    })
    response = client.patch(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/status", json={"status_id": str(uuid4())}
    )
    assert response.status_code == 422


def test_change_lead_status_with_an_invalid_body_is_a_422(client):
    _install(has_permission=True)
    response = client.patch(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/status", json={})
    assert response.status_code == 422


def _bulk_table_responses(**overrides):
    table_responses = {
        "leads": FakeResponse(data=[_lead_row()], count=1),
        "lead_statuses": FakeResponse(
            data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
        ),
        "lead_sources": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
        "lead_tags": FakeResponse(data=[]),
        "allocations": FakeResponse(data=[{"id": str(uuid4()), "status": "new"}]),
    }
    table_responses.update(overrides)
    return table_responses


def test_bulk_action_denied_without_permission(client):
    _install(has_permission=False, table_responses=_bulk_table_responses())
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk", json={"lead_ids": [LEAD_ID], "action": "assign", "member_id": MEMBER_ID}
    )
    assert response.status_code == 403


def test_bulk_action_requires_membership_before_the_permission_check(client):
    """Not a real RLS test (see fake_supabase.py) — proves the bulk
    endpoint is still gated on workspace membership via
    require_workspace_member, same as every other route."""
    _install(has_permission=True, is_member=False, table_responses=_bulk_table_responses())
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk", json={"lead_ids": [LEAD_ID], "action": "assign", "member_id": MEMBER_ID}
    )
    assert response.status_code == 403


def test_bulk_assign_happy_path(client):
    _install(has_permission=True, table_responses=_bulk_table_responses())
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk",
        json={"lead_ids": [LEAD_ID], "action": "assign", "member_id": MEMBER_ID},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["action"] == "assign"
    assert body["total"] == 1
    assert body["succeeded"] == 1
    assert body["failed"] == 0
    assert body["results"][0]["lead_id"] == LEAD_ID
    assert body["results"][0]["success"] is True


def test_bulk_unassign_happy_path(client):
    _install(has_permission=True, table_responses=_bulk_table_responses())
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk", json={"lead_ids": [LEAD_ID], "action": "unassign"}
    )
    assert response.status_code == 200
    assert response.json()["succeeded"] == 1


def test_bulk_change_status_happy_path(client):
    _install(has_permission=True, table_responses=_bulk_table_responses())
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk",
        json={"lead_ids": [LEAD_ID], "action": "change_status", "status_id": STATUS_ID},
    )
    assert response.status_code == 200
    assert response.json()["succeeded"] == 1


def test_bulk_delete_happy_path(client):
    _install(has_permission=True, table_responses=_bulk_table_responses())
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk", json={"lead_ids": [LEAD_ID], "action": "delete"})
    assert response.status_code == 200
    assert response.json()["succeeded"] == 1


def test_bulk_assign_rejects_a_member_id_not_in_this_workspace(client):
    _install(has_permission=True, table_responses=_bulk_table_responses(workspace_members=FakeResponse(data=[])))
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk",
        json={"lead_ids": [LEAD_ID], "action": "assign", "member_id": str(uuid4())},
    )
    assert response.status_code == 422


def test_bulk_change_status_rejects_a_status_id_not_in_this_workspace(client):
    _install(has_permission=True, table_responses=_bulk_table_responses(lead_statuses=FakeResponse(data=[])))
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk",
        json={"lead_ids": [LEAD_ID], "action": "change_status", "status_id": str(uuid4())},
    )
    assert response.status_code == 422


def test_bulk_action_with_no_lead_ids_is_a_422(client):
    _install(has_permission=True, table_responses=_bulk_table_responses())
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/bulk", json={"lead_ids": [], "action": "delete"})
    assert response.status_code == 422


def test_bulk_action_denied_for_a_workspace_the_caller_is_not_permitted_in(client):
    other_workspace = str(uuid4())
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{other_workspace}/leads/bulk", json={"lead_ids": [LEAD_ID], "action": "delete"})
    assert response.status_code == 403


def test_import_requires_leads_create_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/import", json={"csv_content": "name\nAcme Corp\n"})
    assert response.status_code == 403


def test_import_happy_path_returns_a_summary(client):
    _install(has_permission=True, table_responses=_bulk_table_responses())
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/import",
        json={"csv_content": "name,phone,priority\nAcme Corp,+15551234567,high\n"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["created"] == 1
    assert body["failed"] == 0
    assert body["errors"] == []


def test_import_reports_row_level_errors_for_a_mixed_batch(client):
    _install(has_permission=True, table_responses=_bulk_table_responses())
    csv_content = "name,status\nAcme Corp,New\n,New\n"
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/import", json={"csv_content": csv_content})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    assert body["created"] == 1
    assert body["failed"] == 1
    assert body["errors"][0]["row"] == 3


def test_import_with_empty_csv_content_is_a_422(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/import", json={"csv_content": ""})
    assert response.status_code == 422


def test_workspace_isolation_is_not_bypassable_by_editing_the_url(client):
    """Not a real RLS test (see fake_supabase.py) — this only proves the
    route always routes workspace_id through the permission-checking
    dependency before any query runs, for whichever workspace is in the
    URL."""
    other_workspace = str(uuid4())
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{other_workspace}/leads")
    assert response.status_code == 403


# ---- Phase 15: unified activity feed & lead-level notes ----


def test_lead_activity_denied_without_leads_read_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/activity")
    assert response.status_code == 403


def test_lead_activity_succeeds_and_merges_sources(client):
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=[_lead_row()], count=1),
            "lead_statuses": FakeResponse(
                data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
            ),
            "lead_sources": FakeResponse(data=[]),
            "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
            "lead_tags": FakeResponse(data=[]),
            "interactions": FakeResponse(
                data=[{"id": str(uuid4()), "type": "note", "payload": {"text": "hi"}, "actor_member_id": MEMBER_ID, "created_at": "2026-01-05T00:00:00Z"}],
                count=1,
            ),
            "calls": FakeResponse(data=[], count=0),
            "follow_ups": FakeResponse(data=[], count=0),
            "lead_documents": FakeResponse(data=[], count=0),
            "allocations": FakeResponse(data=[], count=0),
        },
    )
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/activity")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["type"] == "note"


def test_lead_activity_404s_for_a_lead_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={"leads": FakeResponse(data=[])})
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/activity")
    assert response.status_code == 404


def test_create_lead_note_requires_leads_update_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/notes", json={"text": "Called back"})
    assert response.status_code == 403


def test_create_lead_note_happy_path(client):
    _install(
        has_permission=True,
        table_responses={
            "leads": FakeResponse(data=[_lead_row()]),
            "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
            "interactions": FakeResponse(
                data=[{"id": str(uuid4()), "type": "note", "payload": {"text": "Called back"}, "created_at": "2026-01-20T00:00:00Z"}]
            ),
        },
    )
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/notes", json={"text": "Called back"})
    assert response.status_code == 201
    body = response.json()
    assert body["type"] == "note"
    assert body["actor_member"]["id"] == MEMBER_ID


def test_create_lead_note_with_empty_text_is_a_422(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/notes", json={"text": ""})
    assert response.status_code == 422


def test_create_lead_note_404s_for_a_lead_not_in_this_workspace(client):
    _install(has_permission=True, table_responses={"leads": FakeResponse(data=[])})
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/notes", json={"text": "hi"})
    assert response.status_code == 404
