from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Query, UploadFile
from supabase import Client

from app.api.dependencies import require_permission
from app.schemas.customer360 import DocumentListResponse, DocumentOut
from app.schemas.documents import SignedUrlResponse
from app.security.permissions import Permission
from app.services.documents import DocumentService
from app.services.documents.service import SIGNED_URL_EXPIRES_IN_SECONDS

# Phase 21A — Secure Lead Documents. Nested under
# /workspaces/{workspace_id}/leads/{lead_id}/documents, alongside every
# other lead-nested resource (interactions/allocations/follow-ups/calls
# in api/v1/leads.py) — a lead's documents are a property of that lead,
# reachable regardless of is_customer (unlike Customer 360's existing
# read-only GET /customers/{id}/documents, which requires is_customer
# and is left untouched here). Every route is gated on the matching
# documents.* permission from the seeded RBAC catalog
# (supabase/migrations/000013_reference_data.sql) — the same
# lead_documents_select/_insert/_soft_delete RLS policies
# (000014_rls_policies.sql, hardened by 000021) remain the final
# enforcement layer underneath, per this project's "RLS is the final
# security boundary" architecture.
router = APIRouter(tags=["documents"])


def _service(client: Client) -> DocumentService:
    return DocumentService(client)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/documents", response_model=DocumentListResponse)
async def list_lead_documents(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.DOCUMENTS_READ))],
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> DocumentListResponse:
    items, total = _service(client).list_for_lead(workspace_id, lead_id, limit=limit, offset=offset)
    return DocumentListResponse(items=items, total=total, limit=limit, offset=offset)


@router.post("/workspaces/{workspace_id}/leads/{lead_id}/documents", response_model=DocumentOut, status_code=201)
async def upload_lead_document(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.DOCUMENTS_UPLOAD))],
    file: UploadFile = File(...),
) -> DocumentOut:
    """multipart/form-data upload. `file.filename`/`file.content_type`
    are the client's own claims about the file — DocumentService never
    trusts them as-is: the filename is sanitized and re-derived into a
    server-built storage path, and both the extension and the declared
    MIME type are checked against an explicit allowlist before anything
    is stored (see services/documents/validation.py). Read fully into
    memory rather than streamed: the 25MB cap this validates against is
    small enough that buffering the whole upload is not a resource
    concern, and every existing repository/service call in this codebase
    is synchronous, not streaming."""
    content = await file.read()
    return _service(client).upload(
        workspace_id, lead_id, file_name=file.filename or "file", mime_type=file.content_type, content=content
    )


@router.get(
    "/workspaces/{workspace_id}/leads/{lead_id}/documents/{document_id}/signed-url",
    response_model=SignedUrlResponse,
)
async def get_lead_document_signed_url(
    workspace_id: UUID,
    lead_id: UUID,
    document_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.DOCUMENTS_READ))],
) -> SignedUrlResponse:
    """Powers both Preview and Download (§3) — the client opens/saves
    whatever this short-lived, authorized URL points to; there is no
    separate "download" endpoint, since the difference is purely how the
    client's UI presents the same signed URL."""
    url = _service(client).get_signed_url(workspace_id, lead_id, document_id)
    return SignedUrlResponse(url=url, expires_in=SIGNED_URL_EXPIRES_IN_SECONDS)


@router.delete("/workspaces/{workspace_id}/leads/{lead_id}/documents/{document_id}", status_code=204)
async def delete_lead_document(
    workspace_id: UUID,
    lead_id: UUID,
    document_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.DOCUMENTS_DELETE))],
) -> None:
    _service(client).delete(workspace_id, lead_id, document_id)
