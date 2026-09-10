from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import NotFoundError, ValidationError
from app.integrations.storage import DocumentStorage
from app.repositories.documents import DocumentRepository
from app.repositories.lead_reference import MemberRepository
from app.repositories.leads import LeadRepository
from app.services.documents.validation import build_storage_path, sanitize_filename, validate_upload

SIGNED_URL_EXPIRES_IN_SECONDS = 300  # 5 minutes — short-lived per §"Security"/§3 "Preview".


class DocumentService:
    """Phase 21A — Secure Lead Documents. Orchestrates
    DocumentRepository (metadata) + DocumentStorage (file bytes);
    neither is ever called directly from a route (same layering as
    every other feature — api/dependencies.py has already enforced
    membership/permission through the database RPCs before any method
    here runs, and RLS/storage.objects policies remain the actual
    enforcement regardless of what this class does).

    Every method re-derives `workspace_id`/`lead_id`/the uploader's
    member id from the authenticated request context (via
    LeadRepository.get_for_workspace + the `current_member_id` RPC) —
    never from a client-supplied field (§"Never trust client-provided
    workspace/member identity").
    """

    def __init__(self, client: Client):
        self._client = client
        self._documents = DocumentRepository(client)
        self._leads = LeadRepository(client)
        self._members = MemberRepository(client)
        self._storage = DocumentStorage(client)

    # ---- upload (§2) ----

    def upload(
        self, workspace_id: UUID, lead_id: UUID, *, file_name: str, mime_type: str | None, content: bytes
    ) -> dict[str, Any]:
        self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible
        validate_upload(file_name=file_name, mime_type=mime_type, size_bytes=len(content))

        safe_name = sanitize_filename(file_name)
        storage_path = build_storage_path(workspace_id, lead_id, safe_name)
        actor_id = self._current_member_id(workspace_id)

        try:
            self._storage.upload(storage_path, content, mime_type=mime_type or "application/octet-stream")
        except Exception as exc:
            raise ValidationError("Could not store the file. Please try again.", error_code="upload_failed") from exc

        try:
            row = self._documents.create_for_lead(
                workspace_id,
                lead_id,
                uploaded_by_member_id=actor_id,
                storage_path=storage_path,
                file_name=safe_name,
                mime_type=mime_type,
                size_bytes=len(content),
            )
        except Exception:
            # The metadata insert failed after the file was already
            # stored — remove the now-orphaned object so a failed upload
            # never leaves an inconsistent state (a Storage object with
            # no matching lead_documents row, invisible to every list/
            # download path but silently consuming bucket space).
            self._try_remove(storage_path)
            raise

        return self._enrich(workspace_id, row)

    # ---- list (§3 "List") ----

    def list_for_lead(self, workspace_id: UUID, lead_id: UUID, *, limit: int, offset: int) -> tuple[list[dict[str, Any]], int]:
        self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible
        rows, total = self._documents.list_for_lead(workspace_id, lead_id, limit=limit, offset=offset)
        return [self._enrich(workspace_id, r) for r in rows], total

    # ---- preview / download (§3) ----

    def get_signed_url(self, workspace_id: UUID, lead_id: UUID, document_id: UUID) -> str:
        doc = self._get_owned_document(workspace_id, lead_id, document_id)
        return self._storage.create_signed_url(doc["storage_path"], expires_in=SIGNED_URL_EXPIRES_IN_SECONDS)

    # ---- delete (§3 "Delete") ----

    def delete(self, workspace_id: UUID, lead_id: UUID, document_id: UUID) -> None:
        doc = self._get_owned_document(workspace_id, lead_id, document_id)
        # Metadata first: `lead_documents_soft_delete` RLS (documents.delete)
        # is the authoritative check. Once the row is gone, best-effort
        # remove the Storage object too — if that second step fails, the
        # document is already inaccessible via every read path here (list/
        # get_for_workspace both filter deleted_at is null), so a leftover
        # orphaned object is inert, not a partial-failure/security gap.
        self._documents.soft_delete(workspace_id, document_id)
        self._try_remove(doc["storage_path"])

    # ---- helpers ----

    def _get_owned_document(self, workspace_id: UUID, lead_id: UUID, document_id: UUID) -> dict[str, Any]:
        """404s unless the document exists, belongs to this workspace,
        AND belongs to `lead_id` specifically — a document id valid in
        this workspace but attached to a *different* lead must never be
        reachable through another lead's URL."""
        self._leads.get_for_workspace(workspace_id, lead_id)
        doc = self._documents.get_for_workspace(workspace_id, document_id)
        if doc is None or str(doc.get("lead_id")) != str(lead_id):
            raise NotFoundError(f"Document {document_id} not found.")
        return doc

    def _try_remove(self, storage_path: str) -> None:
        try:
            self._storage.remove(storage_path)
        except Exception:
            pass

    def _enrich(self, workspace_id: UUID, row: dict[str, Any]) -> dict[str, Any]:
        uploader_id = row.get("uploaded_by_member_id")
        item = dict(row)
        item["uploaded_by_member"] = (
            {"id": uploader_id, "full_name": self._members.map_names(workspace_id, [uploader_id]).get(uploader_id)}
            if uploader_id
            else None
        )
        return item

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id
