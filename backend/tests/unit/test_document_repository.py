from uuid import uuid4

import pytest

from app.repositories.documents import DocumentRepository
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
LEAD_ID = uuid4()


def _row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "lead_id": str(LEAD_ID),
        "uploaded_by_member_id": str(uuid4()),
        "storage_bucket": "lead-documents",
        "storage_path": f"{WORKSPACE_ID}/{LEAD_ID}/file.pdf",
        "file_name": "file.pdf",
        "mime_type": "application/pdf",
        "size_bytes": 1024,
        "deleted_at": None,
        "created_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def test_list_for_lead_returns_rows_and_total():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[_row()], count=1)})
    repo = DocumentRepository(client)

    rows, total = repo.list_for_lead(WORKSPACE_ID, LEAD_ID)

    assert len(rows) == 1
    assert total == 1
    assert client.table_calls == ["lead_documents"]


def test_list_recent_for_lead_returns_rows():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[_row(), _row()])})
    repo = DocumentRepository(client)

    rows = repo.list_recent_for_lead(WORKSPACE_ID, LEAD_ID, limit=5)

    assert len(rows) == 2


def test_count_for_lead_returns_the_configured_count():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[_row()], count=7)})
    repo = DocumentRepository(client)

    assert repo.count_for_lead(WORKSPACE_ID, LEAD_ID) == 7


def test_count_for_lead_defaults_to_zero_when_uncounted():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[])})
    repo = DocumentRepository(client)

    assert repo.count_for_lead(WORKSPACE_ID, LEAD_ID) == 0


# ---- Phase 21A additions: create_for_lead / get_for_workspace / soft_delete ----


def test_create_for_lead_inserts_a_server_derived_row():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[_row()])})
    repo = DocumentRepository(client)
    uploader_id = uuid4()

    row = repo.create_for_lead(
        WORKSPACE_ID,
        LEAD_ID,
        uploaded_by_member_id=uploader_id,
        storage_path=f"{WORKSPACE_ID}/{LEAD_ID}/abc_file.pdf",
        file_name="file.pdf",
        mime_type="application/pdf",
        size_bytes=1024,
    )

    assert row["file_name"] == "file.pdf"
    assert client.table_calls == ["lead_documents"]


def test_create_for_lead_allows_a_null_uploader():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[_row(uploaded_by_member_id=None)])})
    repo = DocumentRepository(client)

    row = repo.create_for_lead(
        WORKSPACE_ID,
        LEAD_ID,
        uploaded_by_member_id=None,
        storage_path=f"{WORKSPACE_ID}/{LEAD_ID}/abc_file.pdf",
        file_name="file.pdf",
        mime_type="application/pdf",
        size_bytes=1024,
    )

    assert row["uploaded_by_member_id"] is None


def test_get_for_workspace_returns_the_row_when_found():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[_row()])})
    repo = DocumentRepository(client)

    doc = repo.get_for_workspace(WORKSPACE_ID, uuid4())

    assert doc is not None
    assert doc["file_name"] == "file.pdf"


def test_get_for_workspace_returns_none_when_missing():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=None)})
    repo = DocumentRepository(client)

    assert repo.get_for_workspace(WORKSPACE_ID, uuid4()) is None


def test_soft_delete_sets_deleted_at_and_returns_the_row():
    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[_row(deleted_at="2026-02-01T00:00:00Z")])})
    repo = DocumentRepository(client)

    row = repo.soft_delete(WORKSPACE_ID, uuid4())

    assert row["deleted_at"] is not None


def test_soft_delete_raises_not_found_when_no_row_matched():
    from app.core.exceptions import NotFoundError

    client = FakeSupabaseClient(table_responses={"lead_documents": FakeResponse(data=[])})
    repo = DocumentRepository(client)

    with pytest.raises(NotFoundError):
        repo.soft_delete(WORKSPACE_ID, uuid4())
