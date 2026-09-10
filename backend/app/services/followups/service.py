from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ValidationError
from app.core.timeparse import parse_supabase_datetime
from app.repositories.followups import FollowUpRepository
from app.repositories.lead_reference import MemberRepository
from app.repositories.leads import LeadRepository
from app.services.notifications import notify


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class FollowUpService:
    """Orchestrates follow_ups + the existing leads/workspace_members
    repositories into the shapes api/v1/followups.py returns. Same
    division of responsibility as LeadService (services/leads/service.py):
    authorization is never re-decided here — every method assumes the
    caller (a route, via api/dependencies.py) already enforced
    membership/permission through the database RPCs. This class only
    assembles data, using a request-scoped, user-authenticated `Client`
    so RLS still applies underneath regardless.
    """

    def __init__(self, client: Client):
        self._client = client
        self._follow_ups = FollowUpRepository(client)
        self._leads = LeadRepository(client)
        self._members = MemberRepository(client)

    # ---- follow-ups (Phase 7) ----

    def list_follow_ups(
        self,
        workspace_id: UUID,
        *,
        lead_id: UUID | None,
        status: str | None,
        limit: int,
        offset: int,
    ) -> tuple[list[dict[str, Any]], int]:
        rows, total = self._follow_ups.list_for_workspace(
            workspace_id, lead_id=lead_id, status=status, limit=limit, offset=offset
        )
        return self._enrich(workspace_id, rows), total

    def get_follow_up(self, workspace_id: UUID, follow_up_id: UUID) -> dict[str, Any]:
        row = self._follow_ups.get_for_workspace(workspace_id, follow_up_id)
        return self._enrich(workspace_id, [row])[0]

    def list_lead_follow_ups(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        # 404s if the lead doesn't exist or isn't visible to this caller
        # — same "never trust workspace_id/lead_id without validation"
        # rule as LeadService.list_interactions/list_allocations.
        self._leads.get_for_workspace(workspace_id, lead_id)
        rows = self._follow_ups.list_for_lead(workspace_id, lead_id)
        return self._enrich(workspace_id, rows)

    def create_follow_up(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        """§3: a follow-up must belong to an existing lead in the SAME
        workspace (enforced by re-fetching the lead through
        get_for_workspace, which is workspace-scoped and 404s otherwise
        — the composite FK on follow_ups.lead_id makes a cross-workspace
        reference structurally impossible either way, this is defense in
        depth plus the 404). `created_by_member_id` is always
        current_member_id(), never the client's input.

        `assigned_member_id`: if the client supplies one, it's validated
        active-in-this-workspace via MemberRepository.get_active() (same
        check Phase 6's assign_lead uses) — never trusted un-checked.
        If omitted, defaults to the creator (self-assign), since
        follow_ups.assigned_member_id is NOT NULL. Assigning to someone
        else on create (not just self) is intentionally allowed here:
        follow_ups_insert RLS only requires the followups.create
        permission, not assigned_member_id = current_member_id — every
        role that can create follow-ups is meant to be able to hand one
        to a teammate (e.g. a manager assigning follow-up work), unlike
        follow_ups_update, whose RLS WITH CHECK clause does pin
        reassignment to managers only (see update_follow_up below)."""
        created_by = self._current_member_id(workspace_id)
        lead_id = data["lead_id"]
        lead = self._leads.get_for_workspace(workspace_id, lead_id)

        assigned_member_id = data.get("assigned_member_id")
        if assigned_member_id is not None:
            member = self._members.get_active(workspace_id, assigned_member_id)
            if member is None:
                raise ValidationError("Selected member is not an active member of this workspace.")
            assigned_member_id = str(assigned_member_id)
        else:
            assigned_member_id = created_by

        payload = {
            "lead_id": str(lead_id),
            "assigned_member_id": assigned_member_id,
            "created_by_member_id": created_by,
            "type": data.get("type") or "task",
            "due_at": _iso(data["due_at"]),
            "notes": data.get("notes"),
        }
        row = self._follow_ups.create_for_workspace(workspace_id, payload)

        # Phase 10 §2: notify the assignee, unless they were assigned to
        # themselves. There's no dedicated 'followup_assigned' value in
        # notifications.type's CHECK constraint (000011_notifications_audit.sql
        # only has followup_reminder/followup_overdue, which are
        # due-date-driven and need a scheduled job Phase 10 explicitly
        # doesn't add) — 'system' is the existing type for an event the
        # schema has no dedicated value for, so this uses that rather
        # than a new migration.
        if assigned_member_id != created_by:
            notify(
                workspace_id,
                recipient_member_id=assigned_member_id,
                type="system",
                title="New follow-up assigned to you",
                body=lead.get("name"),
                related_entity_type="follow_up",
                related_entity_id=row["id"],
            )

        return self._enrich(workspace_id, [row])[0]

    def update_follow_up(self, workspace_id: UUID, follow_up_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        """Covers edit, reschedule, reassignment, and status transitions
        (§2D/§2E) — all through one PATCH. `completed_at`/`cancelled_at`
        are never accepted from the client (FollowUpUpdate has no such
        fields); they're derived here from `status` so they can never
        drift out of sync with it: moving to 'completed' stamps
        completed_at and clears cancelled_at, moving to 'cancelled' is
        the mirror image, and moving back to 'pending' clears both
        (a rare "reopen" case, but a status the schema explicitly
        supports, so leaving stale timestamps behind would be wrong).

        Reassignment here goes through the same active-member validation
        as create, but is additionally restricted by RLS itself: unlike
        follow_ups_insert, the follow_ups_update policy's WITH CHECK
        clause requires (is_manager_or_above OR assigned_member_id =
        current_member_id) — so a non-manager team_mate attempting to
        reassign a follow-up away from themselves fails at the database
        even if this service layer had a bug. No new migration was
        needed for Phase 7 because of that: RLS already closes the gap
        Phase 6 had to add a trigger for on `leads`."""
        existing = self._follow_ups.get_for_workspace(workspace_id, follow_up_id)  # 404s if missing/not visible
        previous_assigned_member_id = existing.get("assigned_member_id")

        payload: dict[str, Any] = {}
        if "due_at" in data and data["due_at"] is not None:
            payload["due_at"] = _iso(data["due_at"])
        if "type" in data and data["type"] is not None:
            payload["type"] = data["type"]
        if "notes" in data:
            payload["notes"] = data["notes"]
        if "assigned_member_id" in data and data["assigned_member_id"] is not None:
            member = self._members.get_active(workspace_id, data["assigned_member_id"])
            if member is None:
                raise ValidationError("Selected member is not an active member of this workspace.")
            payload["assigned_member_id"] = str(data["assigned_member_id"])
        if "status" in data and data["status"] is not None:
            status = data["status"]
            payload["status"] = status
            if status == "completed":
                payload["completed_at"] = _now_iso()
                payload["cancelled_at"] = None
            elif status == "cancelled":
                payload["cancelled_at"] = _now_iso()
                payload["completed_at"] = None
            else:  # back to 'pending'
                payload["completed_at"] = None
                payload["cancelled_at"] = None

        if not payload:
            raise ValidationError("No fields to update.")

        updated = self._follow_ups.update_for_workspace(workspace_id, follow_up_id, payload)

        # Phase 10 §2: notify on an actual hand-off to someone else —
        # not on every PATCH (edits/reschedules/status changes are not
        # reassignments), and not when a member reassigns a follow-up to
        # themselves. Same 'system' type as create_follow_up's
        # assignment notification, for the same reason (no dedicated
        # CHECK value for this event).
        new_assigned_member_id = payload.get("assigned_member_id")
        if new_assigned_member_id is not None and new_assigned_member_id != previous_assigned_member_id:
            actor = self._current_member_id(workspace_id)
            if new_assigned_member_id != actor:
                lead = self._leads.get_for_workspace(workspace_id, existing["lead_id"])
                notify(
                    workspace_id,
                    recipient_member_id=new_assigned_member_id,
                    type="system",
                    title="Follow-up reassigned to you",
                    body=lead.get("name"),
                    related_entity_type="follow_up",
                    related_entity_id=str(follow_up_id),
                )

        return self._enrich(workspace_id, [updated])[0]

    # ---- helpers ----

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id

    def _enrich(self, workspace_id: UUID, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not rows:
            return []
        lead_ids = {r["lead_id"] for r in rows}
        lead_names = self._leads.list_names(workspace_id, list(lead_ids))
        member_ids = {r.get("assigned_member_id") for r in rows} | {r.get("created_by_member_id") for r in rows}
        member_names = self._members.map_names(workspace_id, [m for m in member_ids if m])

        now = datetime.now(timezone.utc)
        enriched = []
        for r in rows:
            am_id = r.get("assigned_member_id")
            cb_id = r.get("created_by_member_id")
            item = dict(r)
            item["lead"] = {"id": r["lead_id"], "name": lead_names.get(r["lead_id"], "Unknown lead")}
            item["assigned_member"] = {"id": am_id, "full_name": member_names.get(am_id)} if am_id else None
            item["created_by_member"] = {"id": cb_id, "full_name": member_names.get(cb_id)} if cb_id else None
            item["is_overdue"] = r["status"] == "pending" and _parse(r["due_at"]) < now
            enriched.append(item)
        return enriched


def _iso(value: Any) -> str:
    return value.isoformat() if hasattr(value, "isoformat") else str(value)


_parse = parse_supabase_datetime
