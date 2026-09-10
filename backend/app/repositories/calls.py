from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.repositories.base import BaseRepository


class CallRepository(BaseRepository):
    """`calls` (supabase/migrations/000009_calls_followups.sql). Read-only
    methods (`list_recent_for_lead`/`count_for_lead`) date from Phase 8's
    Customer 360/timeline, which explicitly left calling itself out of
    scope (§5 "Strictly out of scope") — in an environment with no calls
    logged yet, they simply return an empty list/zero, which the
    timeline renders as no call events rather than fabricating any.
    Phase 9 adds the write path (`create_for_workspace`) and the
    workspace-wide/single-call reads the Call Log Foundation needs
    (`list_for_workspace`/`get_for_workspace`) — mirrors
    `FollowUpRepository`'s shape exactly. No DELETE anywhere: calls are
    permanent history (000014_rls_policies.sql: "no DELETE policy
    anywhere")."""

    table_name = "calls"

    def list_for_workspace(
        self,
        workspace_id: UUID,
        *,
        lead_id: UUID | None = None,
        direction: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> tuple[list[dict[str, Any]], int]:
        query = self._client.table("calls").select("*", count="exact").eq("workspace_id", str(workspace_id))
        if lead_id is not None:
            query = query.eq("lead_id", str(lead_id))
        if direction is not None:
            query = query.eq("direction", direction)
        query = query.order("started_at", desc=True).range(offset, offset + limit - 1)
        response = query.execute()
        return response.data or [], response.count or 0

    def get_for_workspace(self, workspace_id: UUID, call_id: UUID) -> dict[str, Any]:
        response = (
            self._client.table("calls")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(call_id))
            .maybe_single()
            .execute()
        )
        if response is None or response.data is None:
            # Same message whether the row doesn't exist or RLS hid it
            # (e.g. a team_mate requesting a colleague's call) — matches
            # every other *_for_workspace getter in this codebase.
            raise NotFoundError(f"Call {call_id} not found.")
        return response.data

    def list_recent_for_lead(self, workspace_id: UUID, lead_id: UUID, *, limit: int = 20) -> list[dict[str, Any]]:
        response = (
            self._client.table("calls")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .order("started_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_for_lead(self, workspace_id: UUID, lead_id: UUID) -> int:
        response = (
            self._client.table("calls")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .limit(1)
            .execute()
        )
        return response.count or 0

    def count_since(self, workspace_id: UUID, since_iso: str) -> int:
        """Calls started at/after `since_iso` — Phase 11's "today's calls"
        KPI (the caller passes today's own start-of-day boundary; this
        method has no date-math opinion of its own)."""
        response = (
            self._client.table("calls")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .gte("started_at", since_iso)
            .limit(1)
            .execute()
        )
        return response.count or 0

    def create_for_workspace(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        payload = {**data, "workspace_id": str(workspace_id)}
        try:
            response = self._client.table("calls").insert(payload).execute()
        except APIError as e:
            raise ValidationError(f"Could not log the call: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not log the call.")
        return response.data[0]

    def count_filtered(
        self,
        workspace_id: UUID,
        *,
        agent_member_id: UUID | None = None,
        since: str | None = None,
        until: str | None = None,
        states: list[str] | None = None,
        outcome_id: UUID | None = None,
    ) -> int:
        """General-purpose bounded count for Phase 17's period/productivity
        metrics ("connected calls", "completed calls", per-member call
        counts, all optionally date-windowed) — mirrors `count_since`'s
        single-indexed-count shape, just with the extra optional filters
        those metrics need instead of a family of near-duplicate methods.
        `states` uses `.in_()` rather than `.not_.is_("connected_at",
        "null")` deliberately — the state machine's own `state` column
        (docs/architecture/06-calling-architecture.md) already
        distinguishes a call that was ever connected (`CONNECTED`,
        `ENDED` — `duration_seconds`/`ended_at` are only ever populated
        after a `connected_at` was recorded) from one that never was
        (`FAILED`/`MISSED`/`CANCELLED`), so this reads directly off that
        existing, reliable signal rather than a second one."""
        query = self._client.table("calls").select("id", count="exact").eq("workspace_id", str(workspace_id))
        if agent_member_id is not None:
            query = query.eq("agent_member_id", str(agent_member_id))
        if since is not None:
            query = query.gte("started_at", since)
        if until is not None:
            query = query.lt("started_at", until)
        if states is not None:
            query = query.in_("state", states)
        # `outcome_id` — added in Phase 21C for the personal/team "call
        # count by outcome" report breakdown, looped one call per
        # `call_outcomes` row the same "small, known cardinality" way
        # DashboardService._leads_by_status already loops per status.
        if outcome_id is not None:
            query = query.eq("outcome_id", str(outcome_id))
        response = query.limit(1).execute()
        return response.count or 0

    def list_contacted_lead_ids(
        self, workspace_id: UUID, *, agent_member_id: UUID, since: str | None = None, until: str | None = None
    ) -> set[str]:
        """Distinct leads a member has called in a window — Phase 21C's
        "leads contacted" personal metric (there's no `is_contacted`
        flag anywhere in the schema; a logged call is the one reliable,
        existing signal that a lead was actually contacted). PostgREST
        has no COUNT(DISTINCT ...); this fetches only the `lead_id`
        column, already bounded to one member's own calls in one report
        period (never "all calls" — the same small-window reasoning
        `count_filtered` already relies on for a single member/range),
        and dedupes client-side."""
        query = (
            self._client.table("calls")
            .select("lead_id")
            .eq("workspace_id", str(workspace_id))
            .eq("agent_member_id", str(agent_member_id))
        )
        if since is not None:
            query = query.gte("started_at", since)
        if until is not None:
            query = query.lt("started_at", until)
        rows = query.execute().data or []
        return {row["lead_id"] for row in rows if row.get("lead_id")}

    def duration_stats(
        self,
        workspace_id: UUID,
        *,
        agent_member_id: UUID | None = None,
        since: str | None = None,
        until: str | None = None,
    ) -> tuple[int, float]:
        """Total/average talk-time (seconds) via the
        `report_call_duration_stats` DB function
        (supabase/migrations/000024_report_aggregate_functions.sql) —
        Phase 21C. SUM/AVG have no PostgREST query-builder equivalent
        (every other aggregate in this codebase is a `count="exact"`),
        so this is the one report metric that needs a DB-side function
        rather than the query builder. Runs through this request's own
        RLS-scoped client (see the function's own comment: deliberately
        not `security definer`), so a team_mate's own call still only
        ever sums calls they're allowed to see."""
        response = self._client.rpc(
            "report_call_duration_stats",
            {
                "p_workspace_id": str(workspace_id),
                "p_agent_member_id": str(agent_member_id) if agent_member_id is not None else None,
                "p_since": since,
                "p_until": until,
            },
        ).execute()
        rows = response.data or []
        if not rows:
            return 0, 0.0
        row = rows[0]
        return int(row.get("total_talk_seconds") or 0), float(row.get("average_call_seconds") or 0.0)
