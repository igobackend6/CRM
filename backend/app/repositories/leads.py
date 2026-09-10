from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.repositories.base import BaseRepository


class LeadRepository(BaseRepository):
    """Leads need workspace-scoped, search/paginated queries that
    `BaseRepository`'s generic CRUD doesn't cover, so this subclass adds
    its own query methods rather than forcing them through `list()`/
    `get_by_id()`. RLS remains the real access boundary either way — the
    explicit `.eq('workspace_id', ...)` filters here exist because a
    caller can belong to more than one workspace, and an unfiltered
    query would otherwise mix rows from all of them together (RLS scopes
    *which* workspaces are visible, not which one this request means).

    Soft-deleted rows (`deleted_at is not null`) are always excluded —
    see docs comment on `leads.deleted_at`: leads are never physically
    removed by normal CRUD, so DELETE (Phase 5 §8/§15) is implemented as
    an update setting `deleted_at`, not a SQL DELETE.
    """

    table_name = "leads"

    def list_for_workspace(
        self,
        workspace_id: UUID,
        *,
        search: str | None = None,
        status_id: UUID | None = None,
        is_customer: bool | None = None,
        assigned_member_id: UUID | None = None,
        created_by_member_id: UUID | None = None,
        source_id: UUID | None = None,
        priority: str | None = None,
        created_from: datetime | None = None,
        created_to: datetime | None = None,
        lead_id_in: list[str] | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> tuple[list[dict[str, Any]], int]:
        query = (
            self._client.table("leads")
            .select("*", count="exact")
            .eq("workspace_id", str(workspace_id))
            .is_("deleted_at", "null")
        )
        if status_id is not None:
            query = query.eq("status_id", str(status_id))
        # `is_customer` — added in Phase 11 so DashboardService can reuse
        # this one method for the "customers" KPI (`limit=1`, discard the
        # row, keep `total`) instead of a second, near-identical count
        # query — same "leads is the source of truth for customers"
        # design as the rest of Customer 360.
        if is_customer is not None:
            query = query.eq("is_customer", is_customer)
        # `assigned_member_id`/`source_id` — added in Phase 12 so
        # PipelineService can reuse this one method for the pipeline's
        # optional assigned-member/source filters instead of a second,
        # near-identical query.
        if assigned_member_id is not None:
            query = query.eq("assigned_member_id", str(assigned_member_id))
        # `created_by_member_id` — added in Phase 21C so ReportService can
        # reuse this one method for the "leads created (by me)" personal
        # report metric instead of a new query — distinct from
        # `assigned_member_id`, which is "leads created (for me)"/"leads
        # I currently own" (leads.created_by_member_id and
        # assigned_member_id are independent columns: a lead is often
        # bulk-imported or created by one member and assigned to
        # another).
        if created_by_member_id is not None:
            query = query.eq("created_by_member_id", str(created_by_member_id))
        if source_id is not None:
            query = query.eq("source_id", str(source_id))
        # `priority`/`created_from`/`created_to`/`lead_id_in` — added in
        # Phase 14 for the Lead List's advanced filters. `lead_id_in` is
        # how a tag filter reaches this method: LeadService resolves
        # "leads tagged X" to a set of ids via LeadTagRepository first
        # (tags are a many-to-many join, not a column on `leads` itself),
        # then intersects that set here — same "one query builder, callers
        # narrow it" shape as every other filter on this method.
        if priority is not None:
            query = query.eq("priority", priority)
        if created_from is not None:
            query = query.gte("created_at", created_from.isoformat())
        if created_to is not None:
            query = query.lte("created_at", created_to.isoformat())
        if lead_id_in is not None:
            if not lead_id_in:
                # The tag matched no leads in this workspace — nothing
                # else can match either, so skip issuing a query with an
                # empty `.in_()` (which some backends handle oddly).
                return [], 0
            query = query.in_("id", lead_id_in)
        if search:
            # ilike wildcards/commas in user input are stripped, not
            # escaped — a false-negative (fewer matches) is an acceptable
            # trade-off for a foundation-phase search box, and it avoids
            # building raw filter strings from unsanitized input.
            term = search.replace("%", "").replace(",", "").replace("*", "").strip()
            if term:
                query = query.or_(f"name.ilike.%{term}%,phone.ilike.%{term}%,email.ilike.%{term}%")
        query = query.order("created_at", desc=True).range(offset, offset + limit - 1)
        response = query.execute()
        return response.data or [], response.count or 0

    def get_for_workspace(self, workspace_id: UUID, lead_id: UUID) -> dict[str, Any]:
        response = (
            self._client.table("leads")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(lead_id))
            .is_("deleted_at", "null")
            .maybe_single()
            .execute()
        )
        if response is None or response.data is None:
            # Same message whether the row doesn't exist or RLS hid it —
            # see NotFoundError's docstring.
            raise NotFoundError(f"Lead {lead_id} not found.")
        return response.data

    def create_for_workspace(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        payload = {**data, "workspace_id": str(workspace_id)}
        try:
            response = self._client.table("leads").insert(payload).execute()
        except APIError as e:
            raise ValidationError(f"Could not create lead: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not create the lead.")
        return response.data[0]

    def update_for_workspace(self, workspace_id: UUID, lead_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        try:
            response = (
                self._client.table("leads")
                .update(data)
                .eq("workspace_id", str(workspace_id))
                .eq("id", str(lead_id))
                .is_("deleted_at", "null")
                .execute()
            )
        except APIError as e:
            raise ValidationError(f"Could not update lead: {e.message}") from e
        if not response.data:
            raise NotFoundError(f"Lead {lead_id} not found (or not permitted to update).")
        return response.data[0]

    def soft_delete_for_workspace(self, workspace_id: UUID, lead_id: UUID) -> dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        return self.update_for_workspace(workspace_id, lead_id, {"deleted_at": now})

    def count_converted(
        self,
        workspace_id: UUID,
        *,
        since: str | None = None,
        until: str | None = None,
        assigned_member_id: UUID | None = None,
        source_id: UUID | None = None,
    ) -> int:
        """Converted leads (`is_customer = true`, optionally scoped to a
        `converted_at` window) — Phase 17's "converted leads" metric.
        Reuses the same `is_customer` flag `list_for_workspace`'s
        `is_customer` filter already relies on (000008_leads.sql: a lead
        can't be `is_customer = true` without `converted_at` set — see
        `leads_converted_at_requires_customer`), just as a dedicated
        count query instead of the "list with limit=1" trick, since the
        date-window filter here doesn't fit `list_for_workspace`'s
        existing filter set. `assigned_member_id`/`source_id` — added in
        Phase 21C for personal/team conversion-rate and pipeline
        source-performance reports."""
        query = (
            self._client.table("leads")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .is_("deleted_at", "null")
            .eq("is_customer", True)
        )
        if since is not None:
            query = query.gte("converted_at", since)
        if until is not None:
            query = query.lt("converted_at", until)
        if assigned_member_id is not None:
            query = query.eq("assigned_member_id", str(assigned_member_id))
        if source_id is not None:
            query = query.eq("source_id", str(source_id))
        response = query.limit(1).execute()
        return response.count or 0

    def list_rechurn_candidates(
        self,
        workspace_id: UUID,
        *,
        segment: str | None = None,
        updated_before: datetime | None = None,
        lost_status_ids: list[str] | None = None,
        status_id: UUID | None = None,
        source_id: UUID | None = None,
        assigned_member_id: UUID | None = None,
        priority: str | None = None,
        search: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> tuple[list[dict[str, Any]], int]:
        """Phase 19 — Rechurn queue candidates: non-customer leads that
        are either stale (`updated_at` older than `updated_before`) or
        sitting in a workspace-configured 'lost' status
        (`lead_statuses.stage='closed_lost'` — resolved by RechurnService, never a
        hardcoded status id/name here). A dedicated method rather than a
        new branch on `list_for_workspace`, for the same reason
        `count_converted` above is dedicated: "stale OR lost" is an OR of
        two independent conditions, which doesn't fit that method's
        existing all-AND filter set.

        `segment=None` (the default "all candidates" view) expresses the
        OR as a single extra `.or_()` filter, combined via AND with every
        other already-applied `.eq()`/`.or_()` filter (calling `.or_()`
        twice on one postgrest-py query builder adds two independent
        `or=(...)` query params, which PostgREST ANDs together — the same
        mechanism `search` below already relies on to combine with every
        other filter here). `segment="inactive"`/`"lost"` narrow to just
        one condition, each expressed as a plain AND-composable filter.
        """
        lost_ids = lost_status_ids or []
        if segment == "lost" and not lost_ids:
            # No status in this workspace is configured as 'lost' —
            # nothing can match; never guess a fallback status (see
            # docstring above and RechurnService's own note on this).
            return [], 0

        query = (
            self._client.table("leads")
            .select("*", count="exact")
            .eq("workspace_id", str(workspace_id))
            .is_("deleted_at", "null")
            .eq("is_customer", False)
        )
        if status_id is not None:
            query = query.eq("status_id", str(status_id))
        if source_id is not None:
            query = query.eq("source_id", str(source_id))
        if assigned_member_id is not None:
            query = query.eq("assigned_member_id", str(assigned_member_id))
        if priority is not None:
            query = query.eq("priority", priority)

        if segment == "inactive":
            query = query.lt("updated_at", updated_before.isoformat())
        elif segment == "lost":
            query = query.in_("status_id", lost_ids)
        else:
            clauses = [f"updated_at.lt.{updated_before.isoformat()}"]
            if lost_ids:
                clauses.append(f"status_id.in.({','.join(lost_ids)})")
            query = query.or_(",".join(clauses))

        if search:
            term = search.replace("%", "").replace(",", "").replace("*", "").strip()
            if term:
                query = query.or_(f"name.ilike.%{term}%,phone.ilike.%{term}%,email.ilike.%{term}%")

        query = query.order("updated_at").range(offset, offset + limit - 1)
        response = query.execute()
        return response.data or [], response.count or 0

    def list_names(self, workspace_id: UUID, lead_ids: list[str]) -> dict[str, str]:
        """id -> name for a batch of leads, workspace-scoped — added in
        Phase 7 so FollowUpService can show "Lead name" on a follow-up
        (§2A) without each follow-up issuing its own single-lead query
        (N+1; Phase 7 §12). Read-only, additive method on the existing
        Phase 5 repository — no change to any existing method."""
        ids = [i for i in lead_ids if i]
        if not ids:
            return {}
        response = (
            self._client.table("leads")
            .select("id, name")
            .eq("workspace_id", str(workspace_id))
            .in_("id", ids)
            .is_("deleted_at", "null")
            .execute()
        )
        return {row["id"]: row["name"] for row in (response.data or [])}
