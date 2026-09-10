from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.repositories.base import BaseRepository


class FollowUpRepository(BaseRepository):
    """Workspace-scoped follow-up CRUD (Phase 7 §2). Mirrors
    `LeadRepository`'s shape (repositories/leads.py) — explicit
    `.eq('workspace_id', ...)` filters on every query for the same
    reason: a caller can belong to more than one workspace, and RLS
    scopes *which* workspaces are visible, not which one a given request
    means. There is no soft-delete/DELETE here: `follow_ups` has no
    deleted_at column and no DELETE RLS policy at all
    (000014_rls_policies.sql: "no DELETE policy: use status =
    'cancelled'") — cancellation is a status transition, not a
    row removal, so this repository never issues a DELETE.
    """

    table_name = "follow_ups"

    def list_for_workspace(
        self,
        workspace_id: UUID,
        *,
        lead_id: UUID | None = None,
        status: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> tuple[list[dict[str, Any]], int]:
        query = self._client.table("follow_ups").select("*", count="exact").eq("workspace_id", str(workspace_id))
        if lead_id is not None:
            query = query.eq("lead_id", str(lead_id))
        if status is not None:
            query = query.eq("status", status)
        query = query.order("due_at").range(offset, offset + limit - 1)
        response = query.execute()
        return response.data or [], response.count or 0

    def get_for_workspace(self, workspace_id: UUID, follow_up_id: UUID) -> dict[str, Any]:
        response = (
            self._client.table("follow_ups")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(follow_up_id))
            .maybe_single()
            .execute()
        )
        if response is None or response.data is None:
            # Same message whether the row doesn't exist or RLS hid it —
            # matches LeadRepository.get_for_workspace's rationale.
            raise NotFoundError(f"Follow-up {follow_up_id} not found.")
        return response.data

    def list_for_lead(self, workspace_id: UUID, lead_id: UUID, *, limit: int = 50) -> list[dict[str, Any]]:
        response = (
            self._client.table("follow_ups")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .order("due_at")
            .limit(limit)
            .execute()
        )
        return response.data or []

    def list_recent_for_lead(self, workspace_id: UUID, lead_id: UUID, *, limit: int = 20) -> list[dict[str, Any]]:
        """Newest-created-first, bounded window — added in Phase 8 for the
        unified Customer 360 timeline (services/customer360/service.py).
        Ordered by `created_at` (when the follow-up was scheduled/logged),
        not `due_at` (list_for_lead's order, which is about upcoming
        work, not history) — a timeline entry's position should reflect
        when the action entered the system, matching every other source
        table's timeline ordering."""
        response = (
            self._client.table("follow_ups")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_for_lead(self, workspace_id: UUID, lead_id: UUID) -> int:
        response = (
            self._client.table("follow_ups")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .limit(1)
            .execute()
        )
        return response.count or 0

    def list_recent_for_workspace(self, workspace_id: UUID, *, limit: int = 20) -> list[dict[str, Any]]:
        """Newest-created-first, bounded window, workspace-wide — added in
        Phase 11 for the dashboard's recent-activity feed. Mirrors
        `list_recent_for_lead` minus the lead filter (same `created_at`
        ordering rationale: an activity feed reflects when things entered
        the system, not `list_for_workspace`'s `due_at` ordering, which
        is about upcoming work)."""
        response = (
            self._client.table("follow_ups")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_overdue(self, workspace_id: UUID, now_iso: str, *, assigned_member_id: UUID | None = None) -> int:
        """Pending follow-ups whose due date has passed — Phase 11's
        "overdue follow-ups" KPI. A single indexed count query (status +
        due_at), not a Python-side scan of every pending row.
        `assigned_member_id` — added in Phase 21C so the personal report
        can reuse this for "my overdue follow-ups" instead of a new
        method; omitted (dashboard's own call site), it stays
        workspace-wide exactly as before."""
        query = (
            self._client.table("follow_ups")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("status", "pending")
            .lt("due_at", now_iso)
        )
        if assigned_member_id is not None:
            query = query.eq("assigned_member_id", str(assigned_member_id))
        response = query.limit(1).execute()
        return response.count or 0

    def count_filtered(
        self,
        workspace_id: UUID,
        *,
        status: str | None = None,
        assigned_member_id: UUID | None = None,
        since: str | None = None,
        until: str | None = None,
    ) -> int:
        """General bounded count for Phase 21C reports — "total
        follow-ups"/"pending"/"cancelled" breakdowns, windowed on
        `created_at` (when the follow-up entered the system). This
        matches `DashboardService._leads_by_status`'s own "created in
        this window, current status" interpretation (Phase 17), so every
        status breakdown here shares one consistent windowing rule
        instead of each status silently meaning a different date field.
        `count_completed` (windowed on `completed_at`, "completed in this
        window") stays a separate, existing method rather than being
        folded in here — changing what it measures would silently change
        an already-shipped, already-tested Phase 17 value."""
        query = self._client.table("follow_ups").select("id", count="exact").eq("workspace_id", str(workspace_id))
        if status is not None:
            query = query.eq("status", status)
        if assigned_member_id is not None:
            query = query.eq("assigned_member_id", str(assigned_member_id))
        if since is not None:
            query = query.gte("created_at", since)
        if until is not None:
            query = query.lt("created_at", until)
        response = query.limit(1).execute()
        return response.count or 0

    def map_next_pending_for_leads(self, workspace_id: UUID, lead_ids: list[str]) -> dict[str, dict[str, Any]]:
        """lead_id -> its earliest pending follow-up, for a batch of leads
        — added in Phase 19 for the Rechurn queue's "next follow-up"
        column. Same N+1-avoidance shape as LeadRepository.list_names/
        MemberRepository.map_names: one query for the whole page of
        rechurn candidates, not one per lead. Ordered by `due_at`
        ascending (matching `list_for_lead`'s own ordering), so the first
        row seen per lead_id is already its earliest — no client-side
        sort needed."""
        ids = [i for i in lead_ids if i]
        if not ids:
            return {}
        response = (
            self._client.table("follow_ups")
            .select("id, lead_id, type, due_at")
            .eq("workspace_id", str(workspace_id))
            .eq("status", "pending")
            .in_("lead_id", ids)
            .order("due_at")
            .execute()
        )
        result: dict[str, dict[str, Any]] = {}
        for row in response.data or []:
            lead_id = row["lead_id"]
            if lead_id not in result:
                result[lead_id] = row
        return result

    def create_for_workspace(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        payload = {**data, "workspace_id": str(workspace_id)}
        try:
            response = self._client.table("follow_ups").insert(payload).execute()
        except APIError as e:
            raise ValidationError(f"Could not create follow-up: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not create the follow-up.")
        return response.data[0]

    def count_completed(
        self,
        workspace_id: UUID,
        *,
        assigned_member_id: UUID | None = None,
        since: str | None = None,
        until: str | None = None,
    ) -> int:
        """Completed follow-ups, optionally scoped to one member and/or a
        `completed_at` window — Phase 17's period "completed follow-ups"
        metric and per-member productivity count. Deliberately a new
        method rather than adding these filters to `list_for_workspace`
        (whose `status` filter + Phase 11's plain `completed_follow_ups`
        KPI already means "completed, all time" — see
        DashboardService.get_summary; changing that method's own filter
        set could silently change that existing, already-tested value)."""
        query = (
            self._client.table("follow_ups")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("status", "completed")
        )
        if assigned_member_id is not None:
            query = query.eq("assigned_member_id", str(assigned_member_id))
        if since is not None:
            query = query.gte("completed_at", since)
        if until is not None:
            query = query.lt("completed_at", until)
        response = query.limit(1).execute()
        return response.count or 0

    def update_for_workspace(self, workspace_id: UUID, follow_up_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        try:
            response = (
                self._client.table("follow_ups")
                .update(data)
                .eq("workspace_id", str(workspace_id))
                .eq("id", str(follow_up_id))
                .execute()
            )
        except APIError as e:
            raise ValidationError(f"Could not update follow-up: {e.message}") from e
        if not response.data:
            raise NotFoundError(f"Follow-up {follow_up_id} not found (or not permitted to update).")
        return response.data[0]
