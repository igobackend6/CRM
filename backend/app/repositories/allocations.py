from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, ValidationError
from app.repositories.base import BaseRepository


class AllocationRepository(BaseRepository):
    """Assignment/reassignment event history (Phase 6 §2B). Append-only —
    no update/delete methods, matching the table's own RLS (no UPDATE/
    DELETE policy on `allocations` beyond what 000014_rls_policies.sql
    already grants for select/insert/update by managers; this
    repository only ever inserts and lists for Phase 6's scope)."""

    table_name = "allocations"

    def list_for_lead(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        response = (
            self._client.table("allocations")
            .select("id, assigned_member_id, assigned_by_member_id, status, assigned_at, created_at")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .order("assigned_at")
            .execute()
        )
        return response.data or []

    def list_recent_for_lead(self, workspace_id: UUID, lead_id: UUID, *, limit: int = 20) -> list[dict[str, Any]]:
        """Newest-first, bounded window — added in Phase 8 for the unified
        Customer 360 timeline (services/customer360/service.py), which
        needs "most recent N" rather than list_for_lead's full
        oldest-first history (that method's ascending order is required
        by LeadService.list_allocations to compute each row's
        previous_member; this one serves a different, additive need)."""
        response = (
            self._client.table("allocations")
            .select("id, assigned_member_id, assigned_by_member_id, status, assigned_at, created_at")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .order("assigned_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_for_lead(self, workspace_id: UUID, lead_id: UUID) -> int:
        response = (
            self._client.table("allocations")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .limit(1)
            .execute()
        )
        return response.count or 0

    def list_recent_for_workspace(self, workspace_id: UUID, *, limit: int = 20) -> list[dict[str, Any]]:
        """Newest-first, bounded window, workspace-wide — added in Phase 11
        for the dashboard's recent-activity feed. Mirrors
        `list_recent_for_lead` minus the lead filter."""
        response = (
            self._client.table("allocations")
            .select("id, assigned_member_id, assigned_by_member_id, status, assigned_at, created_at")
            .eq("workspace_id", str(workspace_id))
            .order("assigned_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_for_workspace(self, workspace_id: UUID) -> int:
        response = (
            self._client.table("allocations")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .limit(1)
            .execute()
        )
        return response.count or 0

    def create(
        self,
        workspace_id: UUID,
        lead_id: UUID,
        *,
        assigned_member_id: str,
        assigned_by_member_id: str,
    ) -> dict[str, Any]:
        payload = {
            "workspace_id": str(workspace_id),
            "lead_id": str(lead_id),
            "assigned_member_id": assigned_member_id,
            "assigned_by_member_id": assigned_by_member_id,
        }
        try:
            response = self._client.table("allocations").insert(payload).execute()
        except APIError as e:
            raise ValidationError(f"Could not record the allocation: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not record the allocation.")
        return response.data[0]
