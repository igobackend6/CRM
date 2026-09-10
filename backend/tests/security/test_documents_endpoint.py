from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api import dependencies as deps
from app.integrations.storage import DocumentStorage
from app.main import app
from app.schemas.auth import AuthenticatedUser
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = str(uuid4())
LEAD_ID = str(uuid4())
OTHER_LEAD_ID = str(uuid4())
DOCUMENT_ID = str(uuid4())
MEMBER_ID = str(uuid4())


def _lead_row(lead_id=LEAD_ID):
    return {"id": lead_id, "workspace_id": WORKSPACE_ID, "name": "Acme Corp", "deleted_at": None}


def _doc_row(**overrides):
    row = {
        "id": DOCUMENT_ID,
        "workspace_id": WORKSPACE_ID,
        "lead_id": LEAD_ID,
        "uploaded_by_member_id": MEMBER_ID,
        "storage_bucket": "lead-documents",
        "storage_path": f"{WORKSPACE_ID}/{LEAD_ID}/abc_file.pdf",
        "file_name": "file.pdf",
        "mime_type": "application/pdf",
        "size_bytes": 4,
        "deleted_at": None,
        "created_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _base_tables(**overrides):
    tables = {
        "leads": FakeResponse(data=[_lead_row()]),
        "lead_documents": FakeResponse(data=[_doc_row()]),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Rep One"}}]),
    }
    tables.update(overrides)
    return tables


def _install(*, has_permission: bool, table_responses=None):
    fake_client = FakeSupabaseClient(
        table_responses=table_responses if table_responses is not None else _base_tables(),
        rpc_responses={"has_permission": has_permission, "is_workspace_member": True, "current_member_id": MEMBER_ID},
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


@pytest.fixture(autouse=True)
def _stub_storage(monkeypatch):
    """No real Supabase Storage backing these tests — every storage
    operation is stubbed at the DocumentStorage class boundary (the
    same "swap the collaborator" seam test_document_service.py uses at
    the unit level), so these tests prove routing/permission-gating/
    404-shaping through the real HTTP layer without needing network
    I/O."""
    monkeypatch.setattr(DocumentStorage, "upload", lambda self, path, content, *, mime_type: None)
    monkeypatch.setattr(DocumentStorage, "create_signed_url", lambda self, path, *, expires_in: f"https://signed.example/{path}")
    monkeypatch.setattr(DocumentStorage, "remove", lambda self, path: None)


@pytest.fixture
def client():
    return TestClient(app)


# ---- GET .../leads/{lead_id}/documents ----


def test_list_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents")
    assert response.status_code == 401


def test_list_denied_without_documents_read_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents")
    assert response.status_code == 403


def test_list_returns_metadata_only_never_storage_path(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents")
    assert response.status_code == 200
    body = response.json()
    assert body["items"][0]["file_name"] == "file.pdf"
    assert "storage_path" not in body["items"][0]


def test_list_404s_for_a_lead_not_visible_in_this_workspace(client):
    _install(has_permission=True, table_responses=_base_tables(leads=FakeResponse(data=None)))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents")
    assert response.status_code == 404


# ---- POST .../leads/{lead_id}/documents (upload) ----


def test_upload_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents",
        files={"file": ("file.pdf", b"data", "application/pdf")},
    )
    assert response.status_code == 401


def test_upload_denied_without_documents_upload_permission(client):
    _install(has_permission=False)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents",
        files={"file": ("file.pdf", b"data", "application/pdf")},
    )
    assert response.status_code == 403


def test_upload_succeeds_for_an_allowed_file(client):
    _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents",
        files={"file": ("file.pdf", b"data", "application/pdf")},
    )
    assert response.status_code == 201
    assert response.json()["file_name"] == "file.pdf"


def test_upload_rejects_a_disallowed_mime_type_as_422(client):
    _install(has_permission=True)
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents",
        files={"file": ("malware.exe", b"data", "application/x-msdownload")},
    )
    assert response.status_code == 422
    assert response.json()["error_code"] in ("invalid_mime_type", "invalid_extension")


def test_upload_404s_for_a_lead_not_visible_in_this_workspace(client):
    _install(has_permission=True, table_responses=_base_tables(leads=FakeResponse(data=None)))
    response = client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents",
        files={"file": ("file.pdf", b"data", "application/pdf")},
    )
    assert response.status_code == 404


def test_upload_workspace_id_is_taken_from_the_path_not_the_client(client):
    fake_client = _install(has_permission=True)
    client.post(
        f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents",
        files={"file": ("file.pdf", b"data", "application/pdf")},
    )
    assert ("has_permission", {"p_workspace_id": WORKSPACE_ID, "p_permission_code": "documents.upload"}) in fake_client.rpc_calls


# ---- GET .../documents/{document_id}/signed-url ----


def test_signed_url_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}/signed-url")
    assert response.status_code == 401


def test_signed_url_denied_without_documents_read_permission(client):
    _install(has_permission=False)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}/signed-url")
    assert response.status_code == 403


def test_signed_url_returns_a_url_and_its_expiry(client):
    _install(has_permission=True)
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}/signed-url")
    assert response.status_code == 200
    body = response.json()
    assert body["url"].startswith("https://signed.example/")
    assert body["expires_in"] == 300


def test_signed_url_404s_for_a_document_belonging_to_a_different_lead(client):
    """A real, in-workspace document id, but attached to a DIFFERENT
    lead than the one in the URL — must not be reachable this way
    (cross-lead access, not just cross-workspace)."""
    _install(
        has_permission=True,
        table_responses=_base_tables(
            leads=FakeResponse(data=[_lead_row(OTHER_LEAD_ID)]), lead_documents=FakeResponse(data=[_doc_row(lead_id=OTHER_LEAD_ID)])
        ),
    )
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}/signed-url")
    assert response.status_code == 404


def test_signed_url_404s_for_a_document_not_in_this_workspace(client):
    _install(has_permission=True, table_responses=_base_tables(lead_documents=FakeResponse(data=None)))
    response = client.get(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}/signed-url")
    assert response.status_code == 404


# ---- DELETE .../documents/{document_id} ----


def test_delete_requires_authentication(client):
    app.dependency_overrides.clear()
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}")
    assert response.status_code == 401


def test_delete_denied_without_documents_delete_permission(client):
    _install(has_permission=False)
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}")
    assert response.status_code == 403


def test_delete_succeeds_for_an_owned_document(client):
    _install(has_permission=True)
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}")
    assert response.status_code == 204


def test_delete_404s_for_a_document_belonging_to_a_different_lead(client):
    _install(has_permission=True, table_responses=_base_tables(lead_documents=FakeResponse(data=[_doc_row(lead_id=OTHER_LEAD_ID)])))
    response = client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}")
    assert response.status_code == 404


def test_delete_workspace_id_is_taken_from_the_path_not_the_client(client):
    fake_client = _install(has_permission=True)
    client.delete(f"/api/v1/workspaces/{WORKSPACE_ID}/leads/{LEAD_ID}/documents/{DOCUMENT_ID}")
    assert ("has_permission", {"p_workspace_id": WORKSPACE_ID, "p_permission_code": "documents.delete"}) in fake_client.rpc_calls
