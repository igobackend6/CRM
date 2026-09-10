import csv
import io
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.repositories.allocations import AllocationRepository
from app.repositories.lead_reference import (
    InteractionRepository,
    LeadTagRepository,
    MemberRepository,
    LeadSourceRepository,
    LeadStatusRepository,
    TagRepository,
)
from app.repositories.custom_fields import CustomFieldValueRepository
from app.repositories.leads import LeadRepository
from app.services.custom_fields import CustomFieldService
from app.services.notifications import notify

# Mirrors schemas/leads.py's `_PRIORITIES` (kept independent rather than
# importing that module's private constant — this is a plain business
# rule the service layer owns, same as the priority CHECK constraint on
# `leads` itself).
_PRIORITIES = {"low", "medium", "high", "urgent"}


class LeadService:
    """Orchestrates the lead repositories into the shapes api/v1/leads.py
    returns. Deliberately does not re-implement any authorization
    decision — every method here assumes the caller (a route, via
    api/dependencies.py) has already enforced membership/permission
    through the database RPCs; this class only assembles data, using a
    request-scoped, user-authenticated `Client` for every query so RLS
    still applies underneath regardless (see repositories/base.py).
    """

    def __init__(self, client: Client):
        self._client = client
        self._leads = LeadRepository(client)
        self._statuses = LeadStatusRepository(client)
        self._sources = LeadSourceRepository(client)
        self._tags = TagRepository(client)
        self._members = MemberRepository(client)
        self._lead_tags = LeadTagRepository(client)
        self._interactions = InteractionRepository(client)
        self._allocations = AllocationRepository(client)
        self._custom_fields = CustomFieldService(client)
        self._custom_field_values = CustomFieldValueRepository(client)

    # ---- reference data (Phase 5 §5/§6) ----

    def list_statuses(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return self._statuses.list_for_workspace(workspace_id)

    def list_sources(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return self._sources.list_for_workspace(workspace_id)

    def list_tags(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return self._tags.list_for_workspace(workspace_id)

    def create_tag(self, workspace_id: UUID, name: str, color: str | None) -> dict[str, Any]:
        return self._tags.create_for_workspace(workspace_id, {"name": name, "color": color})

    # ---- leads ----

    def list_leads(
        self,
        workspace_id: UUID,
        *,
        search: str | None,
        status_id: UUID | None,
        source_id: UUID | None = None,
        assigned_member_id: UUID | None = None,
        priority: str | None = None,
        is_customer: bool | None = None,
        created_from: datetime | None = None,
        created_to: datetime | None = None,
        tag_id: UUID | None = None,
        limit: int,
        offset: int,
    ) -> tuple[list[dict[str, Any]], int]:
        """Phase 5's search/status filter, extended in Phase 14 with
        source/assigned-member/priority/customer/created-date-range/tag —
        still the one workspace-scoped lead query
        (`LeadRepository.list_for_workspace`), just with more optional
        narrowing params; no second listing method or endpoint.

        Every id-shaped filter is validated against THIS workspace before
        it reaches the query, exactly like `change_lead_status` already
        does for status_id and `bulk_update_leads` does for
        member_id/status_id — a bad id is a 422, not a silently-empty
        result (§"validate status/source/member/tag belongs to current
        workspace")."""
        if status_id is not None and self._statuses.get_for_workspace(workspace_id, status_id) is None:
            raise ValidationError("Selected status does not belong to this workspace.")
        if source_id is not None and self._sources.get_for_workspace(workspace_id, source_id) is None:
            raise ValidationError("Selected source does not belong to this workspace.")
        if assigned_member_id is not None and self._members.get_for_workspace(workspace_id, assigned_member_id) is None:
            raise ValidationError("Selected member does not belong to this workspace.")
        if priority is not None and priority not in _PRIORITIES:
            raise ValidationError(f"priority must be one of {sorted(_PRIORITIES)}")

        lead_id_in: list[str] | None = None
        if tag_id is not None:
            if self._tags.get_for_workspace(workspace_id, tag_id) is None:
                raise ValidationError("Selected tag does not belong to this workspace.")
            lead_id_in = self._lead_tags.list_lead_ids_for_tag(workspace_id, tag_id)

        rows, total = self._leads.list_for_workspace(
            workspace_id,
            search=search,
            status_id=status_id,
            source_id=source_id,
            assigned_member_id=assigned_member_id,
            priority=priority,
            is_customer=is_customer,
            created_from=created_from,
            created_to=created_to,
            lead_id_in=lead_id_in,
            limit=limit,
            offset=offset,
        )
        return self._enrich(workspace_id, rows), total

    def get_lead(self, workspace_id: UUID, lead_id: UUID) -> dict[str, Any]:
        row = self._leads.get_for_workspace(workspace_id, lead_id)
        return self._enrich(workspace_id, [row])[0]

    def create_lead(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        member_id = self._current_member_id(workspace_id)
        status_id = data.get("status_id")
        if status_id is None:
            status_id = self._default_status_id(workspace_id)
        payload = {
            "name": data["name"],
            "phone": data.get("phone"),
            "email": data.get("email"),
            "source_id": str(data["source_id"]) if data.get("source_id") else None,
            "status_id": str(status_id),
            "priority": data.get("priority") or "medium",
            # Never trust a client-supplied owner — the creating member
            # becomes both the assignee and the creator (Phase 5 §9).
            "assigned_member_id": member_id,
            "created_by_member_id": member_id,
        }
        # Validate custom values BEFORE the insert so a bad value doesn't
        # leave a half-created lead. On create, mandatory custom fields
        # are enforced even when the client sends no custom_fields block.
        resolved_custom = self._custom_fields.resolve_values_for_write(
            workspace_id, data.get("custom_fields") or {}, require_mandatory=True
        )
        row = self._leads.create_for_workspace(workspace_id, payload)
        self._custom_fields.write_values(workspace_id, UUID(row["id"]), resolved_custom)
        return self._enrich(workspace_id, [row])[0]

    def update_lead(self, workspace_id: UUID, lead_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        custom = data.pop("custom_fields", None)
        payload = {k: (str(v) if isinstance(v, UUID) else v) for k, v in data.items() if v is not None}
        if not payload and custom is None:
            raise ValidationError("No fields to update.")

        # Partial update — mandatory custom fields are not re-checked
        # (that's a create-time gate), but every supplied value is still
        # type/option validated.
        resolved_custom = (
            self._custom_fields.resolve_values_for_write(workspace_id, custom, require_mandatory=False)
            if custom is not None
            else {}
        )

        if payload:
            row = self._leads.update_for_workspace(workspace_id, lead_id, payload)
        else:
            row = self._leads.get_for_workspace(workspace_id, lead_id)
        self._custom_fields.write_values(workspace_id, lead_id, resolved_custom)
        return self._enrich(workspace_id, [row])[0]

    def delete_lead(self, workspace_id: UUID, lead_id: UUID) -> None:
        # Soft delete only — see LeadRepository's docstring. leads.delete
        # permission is enforced by api/dependencies.py before this runs;
        # RLS additionally enforces it as an UPDATE (leads_update policy)
        # since that's the statement actually issued.
        self._leads.soft_delete_for_workspace(workspace_id, lead_id)

    def change_lead_status(self, workspace_id: UUID, lead_id: UUID, status_id: UUID) -> dict[str, Any]:
        """Phase 12's dedicated status-change endpoint. Reuses
        `update_lead` for the actual write (no duplicate update/enrich
        logic) — this only adds the workspace-scoped status_id check
        first, so a cross-workspace or made-up status_id gets a clean
        422 instead of a raw Postgres FK-violation error (the same
        defense-in-depth already used for assigned_member_id in
        `assign_lead` and outcome_id in CallService)."""
        status = self._statuses.get_for_workspace(workspace_id, status_id)
        if status is None:
            raise ValidationError("Selected status does not belong to this workspace.")
        return self.update_lead(workspace_id, lead_id, {"status_id": status_id})

    def convert_to_customer(self, workspace_id: UUID, lead_id: UUID) -> dict[str, Any]:
        """Phase 18 — Lead -> Customer conversion. A customer IS a lead
        with `is_customer = true` (000008_leads.sql's own docstring); this
        only flips that flag (plus stamping `converted_at`) on the
        existing row — no new record, no data copy, no new table. The
        lead's id never changes, so every related call/follow-up/
        interaction/message/document/allocation (all foreign-keyed to
        `leads.id`) is preserved automatically, unchanged.

        Idempotent-safe: a lead that is already a customer is rejected
        with a 409 (ConflictError) rather than silently re-stamping
        `converted_at` or writing a second conversion activity row —
        "first conversion succeeds, repeated conversion returns a clear
        conflict, never creates duplicates" (Phase 18 §"Conversion")."""
        lead = self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible
        if lead.get("is_customer"):
            raise ConflictError(f"Lead {lead_id} has already been converted to a customer.")

        actor_id = self._current_member_id(workspace_id)
        now = datetime.now(timezone.utc).isoformat()
        updated = self._leads.update_for_workspace(workspace_id, lead_id, {"is_customer": True, "converted_at": now})

        # Conversion activity (Phase 18 §"Conversion Activity") — reuses
        # the existing `interactions` timeline via the `status_change`
        # type `interactions.type` already allows
        # (000010_allocations_interactions.sql) but no earlier phase ever
        # wrote (see CustomerService._assemble_activity's docstring). No
        # new table, no new interaction type.
        self._interactions.create_status_change(
            workspace_id, lead_id, actor_member_id=actor_id, payload={"event": "converted_to_customer"}
        )

        # Notify the assigned member (Phase 10's existing infrastructure,
        # reusing the 'system' type the same way follow-up/call activity
        # already does for an event with no dedicated CHECK value), unless
        # the converting actor IS the assignee — no self-notification.
        assigned_member_id = lead.get("assigned_member_id")
        if assigned_member_id and assigned_member_id != actor_id:
            notify(
                workspace_id,
                recipient_member_id=assigned_member_id,
                type="system",
                title="Lead converted to customer",
                body=lead.get("name"),
                related_entity_type="lead",
                related_entity_id=str(lead_id),
            )

        return self._enrich(workspace_id, [updated])[0]

    # ---- pipeline / sales funnel (Phase 12) ----

    def list_pipeline(
        self,
        workspace_id: UUID,
        *,
        search: str | None,
        assigned_member_id: UUID | None,
        source_id: UUID | None,
        limit: int,
        offset: int,
    ) -> list[dict[str, Any]]:
        """Leads grouped by `lead_statuses`, preserving the workspace's
        configured `sort_order` (Phase 12 §"Status Handling"). One bounded
        `list_for_workspace` query per status (there are only ever a
        handful of statuses per workspace) rather than pulling every
        matching lead workspace-wide and grouping in Python — keeps each
        column's query itself limited/offset/paginated, matching
        §"Support pagination where practical"."""
        statuses = self._statuses.list_for_workspace(workspace_id)  # already sort_order-ordered
        raw_columns: list[tuple[dict[str, Any], list[dict[str, Any]], int]] = []
        all_rows: list[dict[str, Any]] = []
        for status in statuses:
            rows, total = self._leads.list_for_workspace(
                workspace_id,
                search=search,
                status_id=status["id"],
                assigned_member_id=assigned_member_id,
                source_id=source_id,
                limit=limit,
                offset=offset,
            )
            raw_columns.append((status, rows, total))
            all_rows.extend(rows)

        # One batched member-name lookup across every column instead of
        # one per status (Phase 5/7's established N+1-avoidance pattern —
        # see LeadRepository.list_names/MemberRepository.map_names).
        member_ids = {r.get("assigned_member_id") for r in all_rows if r.get("assigned_member_id")}
        member_names = self._members.map_names(workspace_id, list(member_ids))

        columns = []
        for status, rows, total in raw_columns:
            cards = []
            for r in rows:
                am_id = r.get("assigned_member_id")
                cards.append(
                    {
                        "id": r["id"],
                        "name": r["name"],
                        "phone": r.get("phone"),
                        "email": r.get("email"),
                        "priority": r["priority"],
                        "status": status,
                        "assigned_member": {"id": am_id, "full_name": member_names.get(am_id)} if am_id else None,
                        "updated_at": r["updated_at"],
                    }
                )
            columns.append({"status": status, "leads": cards, "total": total})
        return columns

    # ---- bulk actions & CSV import (Phase 13) ----

    def bulk_update_leads(
        self,
        workspace_id: UUID,
        lead_ids: list[UUID],
        action: str,
        *,
        member_id: UUID | None,
        status_id: UUID | None,
    ) -> list[dict[str, Any]]:
        """Phase 13 §"Bulk Actions". Reuses assign_lead/change_lead_status/
        delete_lead verbatim per lead — the exact same write paths (and
        their exact same defense-in-depth id checks/notifications) as the
        single-lead endpoints, so there is no second, duplicate
        implementation of any of those operations.

        The *target* of the action (member_id/status_id) is validated
        once, up front, before touching any lead — an invalid target is a
        bad request, not a per-lead failure, so this never silently
        applies a bad value to some leads and not others
        (§"do not partially perform unsafe operations silently"). Which
        *leads* the action actually succeeds/fails for is a separate,
        expected-to-vary-per-row concern, reported back per lead
        (§"return per-lead success/failure information when practical")
        rather than aborting the whole batch on the first missing lead.
        """
        if action == "assign":
            if member_id is None:
                raise ValidationError("member_id is required for the assign action.")
            if self._members.get_active(workspace_id, member_id) is None:
                raise ValidationError("Selected member is not an active member of this workspace.")
        elif action == "change_status":
            if status_id is None:
                raise ValidationError("status_id is required for the change_status action.")
            if self._statuses.get_for_workspace(workspace_id, status_id) is None:
                raise ValidationError("Selected status does not belong to this workspace.")
        elif action not in ("unassign", "delete"):
            raise ValidationError(f"Unsupported bulk action: {action}")

        results: list[dict[str, Any]] = []
        for lead_id in lead_ids:
            try:
                if action == "assign":
                    self.assign_lead(workspace_id, lead_id, member_id)
                elif action == "unassign":
                    self.assign_lead(workspace_id, lead_id, None)
                elif action == "change_status":
                    self.change_lead_status(workspace_id, lead_id, status_id)
                else:  # "delete"
                    self.delete_lead(workspace_id, lead_id)
                results.append({"lead_id": lead_id, "success": True, "error": None})
            except (NotFoundError, ValidationError) as e:
                # NotFoundError here means "not in this workspace / not
                # visible" (see LeadRepository.get_for_workspace's
                # docstring) — exactly the "validate every lead belongs to
                # the workspace" rule, enforced by the same repository
                # check every single-lead route already relies on, not a
                # second check duplicated here.
                results.append({"lead_id": lead_id, "success": False, "error": str(e)})
        return results

    def import_leads_csv(self, workspace_id: UUID, csv_content: str) -> dict[str, Any]:
        """Phase 13 §"CSV Import". Recognizes name/phone/email/status/
        source/priority — the same fields LeadCreate accepts (Phase 5
        §3), plus status/source resolved by display name/code rather than
        id, since a CSV a rep exports/edits by hand will never contain
        real UUIDs. status/source are resolved ONLY within this
        workspace's own lookups (never trusting an imported id — there IS
        no imported id here at all). `assigned_member_id`/
        `created_by_member_id` are resolved exactly like create_lead():
        always the importing member, never anything from the file.

        One bad row never corrupts another: each row is created (or
        rejected) independently and a per-row failure is caught and
        reported, not raised, so the whole import completes with a
        summary rather than aborting partway through."""
        reader = csv.DictReader(io.StringIO(csv_content))
        if not reader.fieldnames:
            raise ValidationError("CSV file is missing a header row.")
        if "name" not in {(h or "").strip().lower() for h in reader.fieldnames}:
            raise ValidationError("CSV file must have a 'name' column.")

        statuses = self._statuses.list_for_workspace(workspace_id)
        sources = self._sources.list_for_workspace(workspace_id)
        status_lookup = {s["name"].strip().lower(): s["id"] for s in statuses}
        status_lookup.update({s["code"].strip().lower(): s["id"] for s in statuses})
        source_lookup = {s["name"].strip().lower(): s["id"] for s in sources}
        source_lookup.update({s["code"].strip().lower(): s["id"] for s in sources})
        default_status_id = next((s["id"] for s in statuses if s.get("is_default")), None)
        member_id = self._current_member_id(workspace_id)

        total = 0
        created = 0
        errors: list[dict[str, Any]] = []
        for row_number, raw_row in enumerate(reader, start=2):  # row 1 is the header
            total += 1
            row = {(k or "").strip().lower(): (v or "").strip() for k, v in raw_row.items() if k}
            try:
                self._import_one_row(
                    workspace_id,
                    row,
                    member_id=member_id,
                    status_lookup=status_lookup,
                    source_lookup=source_lookup,
                    default_status_id=default_status_id,
                )
                created += 1
            except ValidationError as e:
                errors.append({"row": row_number, "error": str(e)})
        return {"total": total, "created": created, "failed": len(errors), "errors": errors}

    def _import_one_row(
        self,
        workspace_id: UUID,
        row: dict[str, str],
        *,
        member_id: str,
        status_lookup: dict[str, str],
        source_lookup: dict[str, str],
        default_status_id: str | None,
    ) -> None:
        name = row.get("name", "")
        if not name:
            raise ValidationError("name is required.")

        priority = (row.get("priority") or "medium").lower()
        if priority not in _PRIORITIES:
            raise ValidationError(f"invalid priority '{priority}'.")

        status_id = default_status_id
        raw_status = row.get("status")
        if raw_status:
            status_id = status_lookup.get(raw_status.lower())
            if status_id is None:
                raise ValidationError(f"unknown status '{raw_status}'.")
        if status_id is None:
            raise ValidationError("workspace has no default lead status configured.")

        source_id = None
        raw_source = row.get("source")
        if raw_source:
            source_id = source_lookup.get(raw_source.lower())
            if source_id is None:
                raise ValidationError(f"unknown source '{raw_source}'.")

        payload = {
            "name": name,
            "phone": row.get("phone") or None,
            "email": row.get("email") or None,
            "source_id": source_id,
            "status_id": status_id,
            "priority": priority,
            "assigned_member_id": member_id,
            "created_by_member_id": member_id,
        }
        self._leads.create_for_workspace(workspace_id, payload)

    # ---- assignment & allocation history (Phase 6) ----

    def list_workspace_members(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return self._members.list_active(workspace_id)

    def assign_lead(self, workspace_id: UUID, lead_id: UUID, member_id: UUID | None) -> dict[str, Any]:
        """Assign, reassign, or unassign (member_id=None) a lead.

        The allocations-history row and the assignee notification are NOT
        written here — the `leads_on_assignment` trigger
        (000027_lead_assignment_side_effects.sql) writes both on any
        `assigned_member_id` change, so an assignment made from the Admin
        panel's direct UPDATE gets the same side effects as one made
        through this endpoint. Doing it here too would write two
        allocation rows per reassignment.
        """
        self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible

        if member_id is not None:
            # Defense in depth beyond the composite FK on
            # leads.assigned_member_id (which already makes a
            # cross-workspace reference structurally impossible): also
            # reject a removed/suspended/invited member, which the FK
            # alone would still allow to be referenced.
            member = self._members.get_active(workspace_id, member_id)
            if member is None:
                raise ValidationError("Selected member is not an active member of this workspace.")

        updated = self._leads.update_for_workspace(
            workspace_id, lead_id, {"assigned_member_id": str(member_id) if member_id else None}
        )
        return self._enrich(workspace_id, [updated])[0]

    def list_allocations(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible
        rows = self._allocations.list_for_lead(workspace_id, lead_id)  # ascending by assigned_at

        member_ids: set[str] = set()
        for r in rows:
            member_ids.add(r["assigned_member_id"])
            member_ids.add(r["assigned_by_member_id"])
        member_names = self._members.map_names(workspace_id, list(member_ids))

        def summary(member_id: str | None) -> dict[str, Any] | None:
            return {"id": member_id, "full_name": member_names.get(member_id)} if member_id else None

        enriched = []
        previous_member_id: str | None = None
        for r in rows:
            enriched.append(
                {
                    "id": r["id"],
                    "previous_member": summary(previous_member_id),
                    "assigned_member": summary(r["assigned_member_id"]),
                    "assigned_by": summary(r["assigned_by_member_id"]),
                    "status": r["status"],
                    "assigned_at": r["assigned_at"],
                    "created_at": r["created_at"],
                }
            )
            previous_member_id = r["assigned_member_id"]

        # Most-recent-first for display, ascending order was only needed
        # to compute previous_member correctly above.
        enriched.reverse()
        return enriched

    # ---- tags on a lead (Phase 5 §6) ----

    def list_lead_tags(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if not visible
        return self._lead_tags.list_for_lead(workspace_id, lead_id)

    def attach_tag(self, workspace_id: UUID, lead_id: UUID, tag_id: UUID) -> dict[str, Any]:
        self._leads.get_for_workspace(workspace_id, lead_id)
        self._lead_tags.attach(workspace_id, lead_id, tag_id)
        return self._tags.get_by_id(tag_id)

    def detach_tag(self, workspace_id: UUID, lead_id: UUID, tag_id: UUID) -> None:
        self._lead_tags.detach(workspace_id, lead_id, tag_id)

    # ---- interactions (Phase 5 §2, read-only) ----

    def list_interactions(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        self._leads.get_for_workspace(workspace_id, lead_id)
        rows = self._interactions.list_for_lead(workspace_id, lead_id)
        member_names = self._members.map_names(workspace_id, [r.get("actor_member_id") for r in rows])
        enriched = []
        for r in rows:
            actor_id = r.get("actor_member_id")
            item = dict(r)
            item["actor_member"] = {"id": actor_id, "full_name": member_names.get(actor_id)} if actor_id else None
            enriched.append(item)
        return enriched

    # ---- helpers ----

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id

    def _default_status_id(self, workspace_id: UUID) -> str:
        statuses = self._statuses.list_for_workspace(workspace_id)
        default_status = next((s for s in statuses if s.get("is_default")), None)
        if default_status is None:
            raise ValidationError("Workspace has no default lead status configured.")
        return default_status["id"]

    def _enrich(self, workspace_id: UUID, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not rows:
            return []
        status_map = {s["id"]: s for s in self._statuses.list_for_workspace(workspace_id)}
        source_map = {s["id"]: s for s in self._sources.list_for_workspace(workspace_id)}
        member_ids = {r.get("assigned_member_id") for r in rows} | {r.get("created_by_member_id") for r in rows}
        member_names = self._members.map_names(workspace_id, [m for m in member_ids if m])
        lead_ids = [r["id"] for r in rows]
        tag_map = self._lead_tags.map_tags_for_leads(workspace_id, lead_ids)

        # Custom fields: one defs read + one batched values read, then
        # remap {field_id: value} -> {field_code: value} per lead. Same
        # N+1-free shape as tags. Archived fields are included so a value
        # doesn't vanish from a lead the moment an admin archives it.
        cf_defs = self._custom_fields.list_fields(workspace_id)
        cf_code_by_id = {f["id"]: f["code"] for f in cf_defs}
        cf_values = self._custom_field_values.map_for_leads(workspace_id, lead_ids)

        enriched = []
        for r in rows:
            item = dict(r)
            item["status"] = status_map.get(r.get("status_id"))
            item["source"] = source_map.get(r.get("source_id"))
            am_id = r.get("assigned_member_id")
            cb_id = r.get("created_by_member_id")
            item["assigned_member"] = {"id": am_id, "full_name": member_names.get(am_id)} if am_id else None
            item["created_by_member"] = {"id": cb_id, "full_name": member_names.get(cb_id)} if cb_id else None
            item["tags"] = tag_map.get(r["id"], [])
            item["custom_fields"] = {
                cf_code_by_id[fid]: val
                for fid, val in cf_values.get(r["id"], {}).items()
                if fid in cf_code_by_id
            }
            enriched.append(item)
        return enriched
