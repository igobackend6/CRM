"""Phase 21A — Secure Lead Documents. Unit-level coverage for
DocumentService's orchestration (validation -> storage -> metadata),
using FakeSupabaseClient for the database side and a small in-memory
fake for DocumentStorage (assigned directly onto the service instance,
the same "swap out a collaborator for testing" seam used elsewhere in
this codebase — e.g. Phase 20's ai_service_module.get_ai_provider
monkeypatching) since Storage has no real backing here.
"""

from uuid import uuid4

import pytest

from app.core.exceptions import NotFoundError, ValidationError
from app.services.documents.service import DocumentService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()
OTHER_LEAD_ID = uuid4()
MEMBER_ID = uuid4()


class _FakeStorage:
    def __init__(self):
        self.uploaded: list[tuple[str, bytes, str]] = []
        self.removed: list[str] = []
        self.signed_url_calls: list[tuple[str, int]] = []
        self.upload_should_fail = False

    def upload(self, path: str, content: bytes, *, mime_type: str) -> None:
        if self.upload_should_fail:
            raise RuntimeError("simulated storage outage")
        self.uploaded.append((path, content, mime_type))

    def create_signed_url(self, path: str, *, expires_in: int) -> str:
        self.signed_url_calls.append((path, expires_in))
        return f"https://signed.example/{path}"

    def remove(self, path: str) -> None:
        self.removed.append(path)


def _lead_row(lead_id=LEAD_ID):
    return {"id": str(lead_id), "workspace_id": str(WORKSPACE_ID), "name": "Acme Corp", "deleted_at": None}


def _doc_row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": str(LEAD_ID),
        "uploaded_by_member_id": str(MEMBER_ID),
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


def _service(**table_overrides) -> tuple[DocumentService, _FakeStorage, FakeSupabaseClient]:
    tables = {
        "leads": FakeResponse(data=[_lead_row()]),
        "lead_documents": FakeResponse(data=[_doc_row()]),
        "workspace_members": FakeResponse(data=[{"id": str(MEMBER_ID), "profile": {"full_name": "Rep One"}}]),
    }
    tables.update(table_overrides)
    client = FakeSupabaseClient(table_responses=tables, rpc_responses={"current_member_id": str(MEMBER_ID)})
    service = DocumentService(client)
    storage = _FakeStorage()
    service._storage = storage  # swap the real Storage wrapper for the fake
    return service, storage, client


# ---- upload: validation ----


def test_upload_rejects_a_disallowed_extension():
    service, storage, _ = _service()
    with pytest.raises(ValidationError) as exc:
        service.upload(WORKSPACE_ID, LEAD_ID, file_name="malware.exe", mime_type="application/pdf", content=b"data")
    assert exc.value.error_code == "invalid_extension"
    assert storage.uploaded == []


def test_upload_rejects_a_disallowed_mime_type():
    service, storage, _ = _service()
    with pytest.raises(ValidationError) as exc:
        service.upload(WORKSPACE_ID, LEAD_ID, file_name="file.pdf", mime_type="application/x-msdownload", content=b"data")
    assert exc.value.error_code == "invalid_mime_type"
    assert storage.uploaded == []


def test_upload_rejects_an_oversized_file():
    service, storage, _ = _service()
    with pytest.raises(ValidationError) as exc:
        service.upload(
            WORKSPACE_ID, LEAD_ID, file_name="file.pdf", mime_type="application/pdf", content=b"x" * (25 * 1024 * 1024 + 1)
        )
    assert exc.value.error_code == "file_too_large"
    assert storage.uploaded == []


def test_upload_rejects_an_empty_file():
    service, storage, _ = _service()
    with pytest.raises(ValidationError) as exc:
        service.upload(WORKSPACE_ID, LEAD_ID, file_name="file.pdf", mime_type="application/pdf", content=b"")
    assert exc.value.error_code == "empty_file"


def test_upload_sanitizes_a_path_traversal_filename_before_storing():
    service, storage, _ = _service()
    service.upload(WORKSPACE_ID, LEAD_ID, file_name="../../etc/passwd.pdf", mime_type="application/pdf", content=b"data")
    stored_path = storage.uploaded[0][0]
    assert ".." not in stored_path
    assert "etc/passwd" not in stored_path
    assert stored_path.startswith(f"{WORKSPACE_ID}/{LEAD_ID}/")


def test_upload_404s_for_a_lead_not_visible_in_this_workspace():
    service, _, _ = _service(leads=FakeResponse(data=None))
    with pytest.raises(NotFoundError):
        service.upload(WORKSPACE_ID, LEAD_ID, file_name="file.pdf", mime_type="application/pdf", content=b"data")


# ---- upload: success + failure handling ----


def test_upload_succeeds_and_returns_enriched_metadata():
    service, storage, client = _service()
    result = service.upload(WORKSPACE_ID, LEAD_ID, file_name="Report Final.pdf", mime_type="application/pdf", content=b"data")

    assert result["file_name"] == "file.pdf"  # from the configured fake response, proving the row round-tripped
    assert result["uploaded_by_member"]["full_name"] == "Rep One"
    assert len(storage.uploaded) == 1
    assert "lead_documents" in client.table_calls


def test_upload_never_lets_the_client_choose_the_storage_path():
    """The path passed to Storage is always server-built
    ({workspace_id}/{lead_id}/{uuid}_{safe_name}), regardless of
    anything resembling a path in the client-supplied filename."""
    service, storage, _ = _service()
    service.upload(WORKSPACE_ID, LEAD_ID, file_name="a/b/c.pdf", mime_type="application/pdf", content=b"data")
    stored_path = storage.uploaded[0][0]
    assert stored_path.startswith(f"{WORKSPACE_ID}/{LEAD_ID}/")
    assert stored_path.count("/") == 2  # workspace/lead/filename — no extra segments smuggled in


def test_upload_rolls_back_the_storage_object_when_the_metadata_insert_fails():
    """A failed metadata insert must never leave an orphaned file with
    no matching row — the uploaded object is removed again."""
    service, storage, _ = _service(lead_documents=FakeResponse(data=[]))  # insert() -> response.data[0] raises IndexError
    with pytest.raises(IndexError):
        service.upload(WORKSPACE_ID, LEAD_ID, file_name="file.pdf", mime_type="application/pdf", content=b"data")
    assert len(storage.uploaded) == 1
    assert len(storage.removed) == 1
    assert storage.removed[0] == storage.uploaded[0][0]


def test_upload_raises_a_validation_error_when_storage_itself_fails():
    service, storage, _ = _service()
    storage.upload_should_fail = True
    with pytest.raises(ValidationError) as exc:
        service.upload(WORKSPACE_ID, LEAD_ID, file_name="file.pdf", mime_type="application/pdf", content=b"data")
    assert exc.value.error_code == "upload_failed"


# ---- list ----


def test_list_for_lead_404s_for_a_lead_not_visible_in_this_workspace():
    service, _, _ = _service(leads=FakeResponse(data=None))
    with pytest.raises(NotFoundError):
        service.list_for_lead(WORKSPACE_ID, LEAD_ID, limit=20, offset=0)


def test_list_for_lead_returns_enriched_rows():
    service, _, _ = _service(lead_documents=FakeResponse(data=[_doc_row()], count=1))
    items, total = service.list_for_lead(WORKSPACE_ID, LEAD_ID, limit=20, offset=0)
    assert total == 1
    assert items[0]["uploaded_by_member"]["full_name"] == "Rep One"


# ---- signed URL (preview/download) ----


def test_get_signed_url_returns_a_short_lived_url_for_an_owned_document():
    service, storage, _ = _service()
    document_id = uuid4()
    url = service.get_signed_url(WORKSPACE_ID, LEAD_ID, document_id)
    assert url.startswith("https://signed.example/")
    assert storage.signed_url_calls[0][1] == 300  # SIGNED_URL_EXPIRES_IN_SECONDS


def test_get_signed_url_404s_when_the_document_belongs_to_a_different_lead():
    """A document id that's real and in-workspace, but attached to
    ANOTHER lead, must not be reachable through this lead's URL."""
    service, _, _ = _service(lead_documents=FakeResponse(data=[_doc_row(lead_id=str(OTHER_LEAD_ID))]))
    with pytest.raises(NotFoundError):
        service.get_signed_url(WORKSPACE_ID, LEAD_ID, uuid4())


def test_get_signed_url_404s_when_the_document_does_not_exist():
    service, _, _ = _service(lead_documents=FakeResponse(data=None))
    with pytest.raises(NotFoundError):
        service.get_signed_url(WORKSPACE_ID, LEAD_ID, uuid4())


# ---- delete ----


def test_delete_soft_deletes_the_row_and_removes_the_storage_object():
    service, storage, client = _service(lead_documents=FakeResponse(data=[_doc_row()]))
    service.delete(WORKSPACE_ID, LEAD_ID, uuid4())
    assert storage.removed == [_doc_row()["storage_path"]]
    assert "lead_documents" in client.table_calls


def test_delete_404s_when_the_document_belongs_to_a_different_lead():
    service, storage, _ = _service(lead_documents=FakeResponse(data=[_doc_row(lead_id=str(OTHER_LEAD_ID))]))
    with pytest.raises(NotFoundError):
        service.delete(WORKSPACE_ID, LEAD_ID, uuid4())
    assert storage.removed == []


def test_delete_survives_a_storage_removal_failure():
    """The metadata row is already soft-deleted (the source of truth for
    "does this document exist") by the time Storage removal is
    attempted — a failure there must not surface as an error to the
    caller, since the document is already gone from every read path."""

    class _FailingRemoveStorage(_FakeStorage):
        def remove(self, path: str) -> None:
            raise RuntimeError("storage outage")

    service, _, _ = _service(lead_documents=FakeResponse(data=[_doc_row()]))
    service._storage = _FailingRemoveStorage()
    service.delete(WORKSPACE_ID, LEAD_ID, uuid4())  # must not raise
