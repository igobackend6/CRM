from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
CUSTOMER_ID = str(uuid4())
STATUS_ID = str(uuid4())
MEMBER_ID = str(uuid4())


def _lead_row(**overrides):
    row = {
        "id": CUSTOMER_ID,
        "workspace_id": WORKSPACE_ID,
        "name": "Acme Corp",
        "phone": "+15551234567",
        "email": "acme@example.com",
        "priority": "medium",
        "status_id": STATUS_ID,
        "source_id": None,
        "assigned_member_id": MEMBER_ID,
        "created_by_member_id": MEMBER_ID,
        "is_customer": True,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _base_tables(**overrides):
    tables = {
        "leads": FakeResponse(data=[_lead_row()], count=1),
        "lead_statuses": FakeResponse(
            data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]
        ),
        "lead_sources": FakeResponse(data=[]),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
        "lead_tags": FakeResponse(data=[]),
        "interactions": FakeResponse(data=[], count=0),
        "calls": FakeResponse(data=[], count=0),
        "follow_ups": FakeResponse(data=[], count=0),
        "lead_documents": FakeResponse(data=[], count=0),
        "allocations": FakeResponse(data=[], count=0),
    }
    tables.update(overrides)
    return tables


def _install(*, has_permission: bool, is_member: bool = True, table_responses=None):
    fake_client = FakeSupabaseClient(
        table_responses=table_responses if table_responses is not None else _base_tables(),
        rpc_responses={
            "has_permission": has_permission,
            "is_workspace_member": is_member,
            "current_member_id": MEMBER_ID,
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


# ---- GET /customers/{id} ----


def test_get_customer_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}")
    assert response.status_code == 401


def test_get_customer_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}")
    assert response.status_code == 403


def test_get_customer_returns_the_profile(client):
    fake_client = _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}")
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Acme Corp"
    assert body["is_customer"] is True
    assert "leads" in fake_client.table_calls


def test_get_customer_rejects_a_non_customer_lead(client):
    """Phase 8 §8/§16: a lead with is_customer=false is not a valid
    Customer 360 resource, even though it exists and is visible."""
    _install(has_permission=True, table_responses=_base_tables(leads=FakeResponse(data=[_lead_row(is_customer=False)], count=1)))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}")
    assert response.status_code == 404


def test_get_customer_rejects_an_invalid_customer_id(client):
    """Nonexistent or cross-workspace id: get_for_workspace's own
    workspace-scoped lookup 404s either way (never distinguishable)."""
    _install(has_permission=True, table_responses=_base_tables(leads=FakeResponse(data=[])))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{uuid4()}")
    assert response.status_code == 404


# ---- GET /customers/{id}/timeline ----


def test_timeline_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/timeline")
    assert response.status_code == 401


def test_timeline_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/timeline")
    assert response.status_code == 403


def test_timeline_rejects_a_non_customer_lead(client):
    _install(has_permission=True, table_responses=_base_tables(leads=FakeResponse(data=[_lead_row(is_customer=False)], count=1)))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/timeline")
    assert response.status_code == 404


def test_timeline_is_empty_when_no_activity_exists(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/timeline")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0


def test_timeline_maps_real_interaction_rows_and_orders_chronologically(client):
    interaction_row = {
        "id": "int-1",
        "type": "note",
        "payload": {"text": "Left a voicemail"},
        "actor_member_id": MEMBER_ID,
        "created_at": "2026-01-10T00:00:00Z",
    }
    document_row = {
        "id": "doc-1",
        "uploaded_by_member_id": MEMBER_ID,
        "file_name": "proposal.pdf",
        "mime_type": "application/pdf",
        "size_bytes": 512,
        "created_at": "2026-01-01T00:00:00Z",
    }
    _install(
        has_permission=True,
        table_responses=_base_tables(
            interactions=FakeResponse(data=[interaction_row], count=1),
            lead_documents=FakeResponse(data=[document_row], count=1),
        ),
    )
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/timeline")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    assert [i["type"] for i in body["items"]] == ["note", "document"]
    assert body["items"][0]["actor_member"]["full_name"] == "Rep One"


def test_timeline_is_paginated(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/timeline?limit=5&offset=5")
    assert response.status_code == 200
    body = response.json()
    assert body["limit"] == 5
    assert body["offset"] == 5


# ---- GET /customers/{id}/documents ----


def test_documents_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/documents")
    assert response.status_code == 401


def test_documents_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/documents")
    assert response.status_code == 403


def test_documents_returns_metadata(client):
    doc_row = {
        "id": str(uuid4()),
        "uploaded_by_member_id": MEMBER_ID,
        "file_name": "contract.pdf",
        "mime_type": "application/pdf",
        "size_bytes": 2048,
        "created_at": "2026-01-01T00:00:00Z",
    }
    _install(has_permission=True, table_responses=_base_tables(lead_documents=FakeResponse(data=[doc_row], count=1)))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/documents")
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["file_name"] == "contract.pdf"
    # storage_path is deliberately not exposed (schemas/customer360.py docstring).
    assert "storage_path" not in body["items"][0]


def test_documents_empty_state(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/documents")
    assert response.status_code == 200
    assert response.json()["items"] == []


def test_documents_rejects_a_non_customer_lead(client):
    _install(has_permission=True, table_responses=_base_tables(leads=FakeResponse(data=[_lead_row(is_customer=False)], count=1)))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/documents")
    assert response.status_code == 404


# ---- GET /customers/{id}/follow-ups ----


def test_follow_ups_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/follow-ups")
    assert response.status_code == 401


def test_follow_ups_denied_without_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/follow-ups")
    assert response.status_code == 403


def test_follow_ups_aggregates_pending_completed_and_cancelled(client):
    rows = [
        {
            "id": str(uuid4()), "workspace_id": WORKSPACE_ID, "lead_id": CUSTOMER_ID,
            "assigned_member_id": MEMBER_ID, "created_by_member_id": MEMBER_ID,
            "type": "call", "due_at": "2026-02-01T00:00:00Z", "status": "pending",
            "notes": None, "completed_at": None, "cancelled_at": None,
            "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
        },
        {
            "id": str(uuid4()), "workspace_id": WORKSPACE_ID, "lead_id": CUSTOMER_ID,
            "assigned_member_id": MEMBER_ID, "created_by_member_id": MEMBER_ID,
            "type": "task", "due_at": "2026-01-15T00:00:00Z", "status": "completed",
            "notes": None, "completed_at": "2026-01-15T00:00:00Z", "cancelled_at": None,
            "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-15T00:00:00Z",
        },
    ]
    _install(has_permission=True, table_responses=_base_tables(follow_ups=FakeResponse(data=rows)))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/follow-ups")
    assert response.status_code == 200
    statuses = {item["status"] for item in response.json()}
    assert statuses == {"pending", "completed"}


def test_follow_ups_rejects_a_non_customer_lead(client):
    _install(has_permission=True, table_responses=_base_tables(leads=FakeResponse(data=[_lead_row(is_customer=False)], count=1)))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/follow-ups")
    assert response.status_code == 404


# ---- POST /customers/{id}/notes ----


def test_create_note_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/notes", json={"text": "hi"})
    assert response.status_code == 401


def test_create_note_denied_without_permission(client):
    _install(has_permission=False)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/notes", json={"text": "hi"})
    assert response.status_code == 403


def test_create_note_succeeds(client):
    _install(
        has_permission=True,
        table_responses=_base_tables(
            interactions=FakeResponse(
                data=[{"id": str(uuid4()), "type": "note", "payload": {"text": "hi"}, "created_at": "2026-01-20T00:00:00Z"}]
            )
        ),
    )
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/notes", json={"text": "hi"})
    assert response.status_code == 201
    assert response.json()["type"] == "note"


def test_create_note_rejects_empty_text(client):
    _install(has_permission=True)
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/notes", json={"text": ""})
    assert response.status_code == 422


def test_create_note_rejects_a_non_customer_lead(client):
    _install(has_permission=True, table_responses=_base_tables(leads=FakeResponse(data=[_lead_row(is_customer=False)], count=1)))
    response = client.post(f"/api/v1/workspaces/{WORKSPACE_ID}/customers/{CUSTOMER_ID}/notes", json={"text": "hi"})
    assert response.status_code == 404
