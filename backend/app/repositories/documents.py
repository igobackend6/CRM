from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from app.core.exceptions import NotFoundError
from app.repositories.base import BaseRepository


class DocumentRepository(BaseRepository):
    """`lead_documents` (supabase/migrations/000008_leads.sql) access.
    Started read-only in Phase 8 (Customer 360's "Documents" section only
    ever *displayed* metadata) — Phase 21A adds the create/get/soft-delete
    methods actual upload/download/delete needs; the original read
    methods are unchanged.

    Soft-deleted rows (`deleted_at is not null`) are excluded from every
    read here, mirroring LeadRepository's convention — a "deleted"
    document should disappear the same way a soft-deleted lead
    disappears from the leads list. There is deliberately no hard
    `delete()` — `lead_documents_soft_delete` is the only DELETE-shaped
    RLS policy on this table (000014_rls_policies.sql: "Soft-deleted via
    `deleted_at`... not mutated in place"), so the row itself is never
    removed even though its backing Storage object is (see
    services/documents/service.py).
    """

    table_name = "lead_documents"

    def list_for_lead(
        self, workspace_id: UUID, lead_id: UUID, *, limit: int = 20, offset: int = 0
    ) -> tuple[list[dict[str, Any]], int]:
        response = (
            self._client.table("lead_documents")
            .select("*", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .is_("deleted_at", "null")
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
        return response.data or [], response.count or 0

    def list_recent_for_lead(self, workspace_id: UUID, lead_id: UUID, *, limit: int = 20) -> list[dict[str, Any]]:
        """Bounded, newest-first window used by the unified timeline
        (services/customer360/service.py) — see that module's docstring
        for why a bounded per-source window (rather than every document)
        is the multi-source pagination strategy."""
        response = (
            self._client.table("lead_documents")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .is_("deleted_at", "null")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_for_lead(self, workspace_id: UUID, lead_id: UUID) -> int:
        response = (
            self._client.table("lead_documents")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .is_("deleted_at", "null")
            .limit(1)
            .execute()
        )
        return response.count or 0

    def get_for_workspace(self, workspace_id: UUID, document_id: UUID) -> dict[str, Any] | None:
        """Workspace-scoped single-row lookup, used by DocumentService
        before any download/delete — returns `None` (never raises) for a
        missing/cross-workspace/soft-deleted id so the caller can 404
        without distinguishing "doesn't exist" from "not yours", the
        same NotFoundError philosophy every other repository in this
        codebase follows."""
        response = (
            self._client.table("lead_documents")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(document_id))
            .is_("deleted_at", "null")
            .maybe_single()
            .execute()
        )
        return response.data if response is not None else None

    def create_for_lead(
        self,
        workspace_id: UUID,
        lead_id: UUID,
        *,
        uploaded_by_member_id: UUID | None,
        storage_path: str,
        file_name: str,
        mime_type: str | None,
        size_bytes: int | None,
    ) -> dict[str, Any]:
        """Inserts the metadata row *after* the file bytes are already in
        Storage (see DocumentService.upload) — `storage_path`/`file_name`
        here are always server-computed (sanitized filename, server-built
        path), never the client's raw, untrusted values. `lead_documents_insert`
        RLS (000021_rls_actor_identity_hardening.sql) independently
        re-checks documents.upload + that `uploaded_by_member_id` matches
        the caller, so this is defense in depth, not the only check."""
        row = {
            "workspace_id": str(workspace_id),
            "lead_id": str(lead_id),
            "uploaded_by_member_id": str(uploaded_by_member_id) if uploaded_by_member_id else None,
            "storage_bucket": "lead-documents",
            "storage_path": storage_path,
            "file_name": file_name,
            "mime_type": mime_type,
            "size_bytes": size_bytes,
        }
        response = self._client.table("lead_documents").insert(row).execute()
        return response.data[0]

    def soft_delete(self, workspace_id: UUID, document_id: UUID) -> dict[str, Any]:
        """Sets `deleted_at`, gated by `lead_documents_soft_delete` RLS
        (documents.delete). Raises NotFoundError if the row doesn't
        exist, isn't in this workspace, or RLS declines the update —
        deliberately indistinguishable, same as BaseRepository.update."""
        response = (
            self._client.table("lead_documents")
            .update({"deleted_at": datetime.now(timezone.utc).isoformat()})
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(document_id))
            .execute()
        )
        if not response.data:
            raise NotFoundError(f"Document {document_id} not found.")
        return response.data[0]
