from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ValidationError
from app.repositories.followups import FollowUpRepository
from app.repositories.lead_reference import LeadSourceRepository, LeadStatusRepository, MemberRepository
from app.repositories.leads import LeadRepository

# Mirrors services/leads/service.py's own `_PRIORITIES` — kept as an
# independent copy rather than importing that module's private constant,
# same "the service layer owns this plain business rule" reasoning
# LeadService's own comment gives for not importing schemas' constant.
_PRIORITIES = {"low", "medium", "high", "urgent"}

_SEGMENTS = {"inactive", "lost"}

# A workspace admin has no UI (in or out of scope for this phase) to
# configure a rechurn-specific inactivity window, so this is a sane CRM
# default (30 days untouched) rather than a magic number pulled from
# nowhere — always overridable per request via `inactive_days`.
DEFAULT_INACTIVE_DAYS = 30


class RechurnService:
    """Phase 19 — Rechurn / Re-engagement. A read-only queue view over
    the *existing* `leads` table (see LeadRepository.list_rechurn_candidates's
    own docstring for why this is a dedicated query rather than a new
    lifecycle system or table): a rechurn candidate is a non-customer
    lead that is either stale (untouched since `inactive_days` ago, via
    `leads.updated_at`) or sitting in a workspace-configured 'lost'
    status (`lead_statuses.stage='closed_lost'` — never a hardcoded status id/name,
    resolved fresh from this workspace's own configuration on every
    call).

    Every rechurn *action* (call, outcome, status change, follow-up)
    reuses the existing CallService/FollowUpService/LeadService write
    paths unchanged — this class only assembles the read view; see
    api/v1/rechurn.py's own docstring for why there is no separate
    "rechurn action" endpoint.

    Same division of responsibility as every other service in this
    codebase: authorization is never decided here — the caller (a route,
    via api/dependencies.py) has already enforced leads.read before any
    method here runs, and RLS's own leads_select policy
    (000014_rls_policies.sql) independently scopes which leads actually
    come back (a team_mate sees only their own assigned/created leads,
    a manager sees the whole workspace) — the exact same visibility a
    team_mate already gets from `GET /leads`/`GET /pipeline`, not a new
    or looser rule for this queue.
    """

    def __init__(self, client: Client):
        self._client = client
        self._leads = LeadRepository(client)
        self._statuses = LeadStatusRepository(client)
        self._sources = LeadSourceRepository(client)
        self._members = MemberRepository(client)
        self._follow_ups = FollowUpRepository(client)

    def list_queue(
        self,
        workspace_id: UUID,
        *,
        segment: str | None = None,
        inactive_days: int = DEFAULT_INACTIVE_DAYS,
        assigned_member_id: UUID | None = None,
        priority: str | None = None,
        status_id: UUID | None = None,
        source_id: UUID | None = None,
        search: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> tuple[list[dict[str, Any]], int]:
        if segment is not None and segment not in _SEGMENTS:
            raise ValidationError(f"segment must be one of {sorted(_SEGMENTS)}")
        if inactive_days < 1:
            raise ValidationError("inactive_days must be at least 1.")
        if priority is not None and priority not in _PRIORITIES:
            raise ValidationError(f"priority must be one of {sorted(_PRIORITIES)}")
        # Same "validate every id-shaped filter against this workspace
        # before it reaches the query" rule LeadService.list_leads
        # already applies (Phase 14 §"Security") — a bad id is a 422,
        # not a silently-empty result.
        if status_id is not None and self._statuses.get_for_workspace(workspace_id, status_id) is None:
            raise ValidationError("Selected status does not belong to this workspace.")
        if source_id is not None and self._sources.get_for_workspace(workspace_id, source_id) is None:
            raise ValidationError("Selected source does not belong to this workspace.")
        if assigned_member_id is not None and self._members.get_for_workspace(workspace_id, assigned_member_id) is None:
            raise ValidationError("Selected member does not belong to this workspace.")

        statuses = self._statuses.list_for_workspace(workspace_id)
        lost_status_ids = [s["id"] for s in statuses if s.get("stage") == "closed_lost"]
        updated_before = datetime.now(timezone.utc) - timedelta(days=inactive_days)

        rows, total = self._leads.list_rechurn_candidates(
            workspace_id,
            segment=segment,
            updated_before=updated_before,
            lost_status_ids=lost_status_ids,
            status_id=status_id,
            source_id=source_id,
            assigned_member_id=assigned_member_id,
            priority=priority,
            search=search,
            limit=limit,
            offset=offset,
        )
        return self._enrich(workspace_id, rows), total

    # ---- helpers ----

    def _enrich(self, workspace_id: UUID, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not rows:
            return []
        status_map = {s["id"]: s for s in self._statuses.list_for_workspace(workspace_id)}
        member_ids = {r.get("assigned_member_id") for r in rows if r.get("assigned_member_id")}
        member_names = self._members.map_names(workspace_id, list(member_ids))
        lead_ids = [r["id"] for r in rows]
        next_follow_ups = self._follow_ups.map_next_pending_for_leads(workspace_id, lead_ids)

        enriched = []
        for r in rows:
            am_id = r.get("assigned_member_id")
            next_follow_up = next_follow_ups.get(r["id"])
            enriched.append(
                {
                    "id": r["id"],
                    "name": r["name"],
                    "phone": r.get("phone"),
                    "email": r.get("email"),
                    "priority": r["priority"],
                    "status": status_map.get(r.get("status_id")),
                    "assigned_member": {"id": am_id, "full_name": member_names.get(am_id)} if am_id else None,
                    "is_customer": r.get("is_customer", False),
                    "last_activity_at": r["updated_at"],
                    "next_follow_up": next_follow_up,
                }
            )
        return enriched
