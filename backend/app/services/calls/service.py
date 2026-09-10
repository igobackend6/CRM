from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ValidationError
from app.core.timeparse import parse_supabase_datetime
from app.repositories.calls import CallRepository
from app.repositories.lead_reference import CallOutcomeRepository, MemberRepository
from app.repositories.leads import LeadRepository
from app.services.notifications import notify


def _iso(value: Any) -> str:
    if isinstance(value, str):
        return value
    return value.isoformat() if hasattr(value, "isoformat") else str(value)


_parse = parse_supabase_datetime


class CallService:
    """Phase 9 — Calling & Call Log Foundation. Orchestrates `calls` +
    the existing leads/workspace_members/call_outcomes repositories into
    the shapes api/v1/calls.py returns. Same division of responsibility
    as every other service in this codebase: authorization is never
    re-decided here — the caller (a route, via api/dependencies.py) has
    already enforced membership/permission through the database RPCs
    before any method here runs; this class only assembles data through
    a request-scoped, user-authenticated `Client`, so RLS still applies
    underneath regardless (in particular, calls_select's own
    manager-or-self scoping — 000014_rls_policies.sql — filters rows
    here independently of whatever this service does).
    """

    def __init__(self, client: Client):
        self._client = client
        self._calls = CallRepository(client)
        self._leads = LeadRepository(client)
        self._members = MemberRepository(client)
        self._outcomes = CallOutcomeRepository(client)

    # ---- reads (§2/§3/§8) ----

    def list_calls(
        self,
        workspace_id: UUID,
        *,
        lead_id: UUID | None,
        direction: str | None,
        limit: int,
        offset: int,
    ) -> tuple[list[dict[str, Any]], int]:
        rows, total = self._calls.list_for_workspace(workspace_id, lead_id=lead_id, direction=direction, limit=limit, offset=offset)
        return self._enrich(workspace_id, rows), total

    def get_call(self, workspace_id: UUID, call_id: UUID) -> dict[str, Any]:
        row = self._calls.get_for_workspace(workspace_id, call_id)
        return self._enrich(workspace_id, [row])[0]

    def list_lead_calls(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        # 404s if the lead doesn't exist or isn't visible to this caller
        # — same "never trust workspace_id/lead_id without validation"
        # rule as FollowUpService.list_lead_follow_ups. Reuses the exact
        # Phase 8 read path (list_recent_for_lead) rather than adding a
        # near-duplicate query method (§13/"reuse the existing Phase 8
        # call aggregation path where possible").
        self._leads.get_for_workspace(workspace_id, lead_id)
        rows = self._calls.list_recent_for_lead(workspace_id, lead_id, limit=50)
        return self._enrich(workspace_id, rows)

    def list_outcomes(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return self._outcomes.list_for_workspace(workspace_id)

    # ---- write (§4) ----

    def create_call(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        """§4/§9: workspace_id and agent/actor are never trusted from the
        client — agent_member_id always comes from current_member_id(),
        matching calls_insert RLS's own
        `agent_member_id = current_member_id(workspace_id)` requirement
        for a non-manager (000014_rls_policies.sql), so a self-logged
        call always satisfies RLS regardless of the caller's role.

        The lead must belong to THIS workspace (re-fetched via
        get_for_workspace, which 404s otherwise — the composite FK on
        calls.lead_id makes a cross-workspace reference structurally
        impossible either way; this is defense in depth plus the 404,
        same reasoning as FollowUpService.create_follow_up).

        outcome_id, if supplied, is validated as a real call_outcomes row
        in this workspace (§9) — never inserted unchecked.

        state is always 'ENDED' for a manually-logged call (see
        CallCreate's docstring for why); duration is expressed through
        connected_at/ended_at, not a direct duration_seconds write (that
        column is a Postgres GENERATED column and would reject one)."""
        agent_member_id = self._current_member_id(workspace_id)
        lead_id = data["lead_id"]
        lead = self._leads.get_for_workspace(workspace_id, lead_id)

        outcome_id = data.get("outcome_id")
        if outcome_id is not None:
            outcome = self._outcomes.get_for_workspace(workspace_id, outcome_id)
            if outcome is None:
                raise ValidationError("Selected outcome is not valid for this workspace.")

        payload: dict[str, Any] = {
            "lead_id": str(lead_id),
            "agent_member_id": agent_member_id,
            "direction": data["direction"],
            "state": "ENDED",
            "outcome_id": str(outcome_id) if outcome_id else None,
            "notes": data.get("notes"),
        }

        started_at = data.get("started_at")
        if started_at is not None:
            payload["started_at"] = _iso(started_at)

        duration_seconds = data.get("duration_seconds")
        if duration_seconds:
            base = _parse(started_at) if started_at is not None else datetime.now(timezone.utc)
            payload["connected_at"] = _iso(base)
            payload["ended_at"] = _iso(base + timedelta(seconds=duration_seconds))

        row = self._calls.create_for_workspace(workspace_id, payload)

        # Phase 10 §2 "call activity where appropriate": notify the
        # lead's owner when a teammate — not the owner themselves — logs
        # a call on their lead. Skipped when the lead has no owner
        # (nobody to notify) or the logging agent IS the owner (no point
        # notifying yourself). Same 'system' type as the follow-up
        # assignment hooks (no dedicated CHECK value for "a call was
        # logged").
        owner_id = lead.get("assigned_member_id")
        if owner_id and owner_id != agent_member_id:
            notify(
                workspace_id,
                recipient_member_id=owner_id,
                type="system",
                title="Call logged on your lead",
                body=lead.get("name"),
                related_entity_type="call",
                related_entity_id=row["id"],
            )

        return self._enrich(workspace_id, [row])[0]

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
        agent_ids = {r.get("agent_member_id") for r in rows if r.get("agent_member_id")}
        agent_names = self._members.map_names(workspace_id, list(agent_ids))
        outcome_ids = {r.get("outcome_id") for r in rows if r.get("outcome_id")}
        outcomes = self._outcomes.map_by_ids(workspace_id, list(outcome_ids))

        enriched = []
        for r in rows:
            agent_id = r.get("agent_member_id")
            outcome_id = r.get("outcome_id")
            item = dict(r)
            item["lead"] = {"id": r["lead_id"], "name": lead_names.get(r["lead_id"], "Unknown lead")}
            item["agent_member"] = {"id": agent_id, "full_name": agent_names.get(agent_id)} if agent_id else None
            item["outcome"] = outcomes.get(outcome_id) if outcome_id else None
            enriched.append(item)
        return enriched
