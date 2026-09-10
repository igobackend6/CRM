from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.base import BaseRepository


class AIInsightRepository(BaseRepository):
    """`ai_call_insights` (Phase 20 — see 000020_ai_call_insights.sql's
    own docstring for why this is a dedicated, stateful table rather
    than reuse of `interactions`). One evolving row per call — `call_id`
    is UNIQUE, so this repository never creates a second row for the
    same call; `upsert_pending` resets an existing terminal row back to
    `pending` for a re-run instead. Mirrors `LeadRepository`'s
    `*_for_workspace` shape (explicit `.eq('workspace_id', ...)` on
    every query — RLS scopes *which* workspaces are visible, not which
    one a given request means)."""

    table_name = "ai_call_insights"

    def get_for_call(self, workspace_id: UUID, call_id: UUID) -> dict[str, Any] | None:
        response = (
            self._client.table("ai_call_insights")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("call_id", str(call_id))
            .maybe_single()
            .execute()
        )
        return response.data if response else None

    def upsert_pending(self, workspace_id: UUID, call_id: UUID, *, requested_by_member_id: str) -> dict[str, Any]:
        """Creates a fresh 'pending' row for this call, or resets an
        existing terminal (completed/failed) row back to 'pending' for
        a re-run — never a second row for the same call (`call_id` is
        UNIQUE). Concurrent double-processing is prevented one level up,
        by `AIInsightService.request_analysis`'s own guard (mirrors
        Phase 18's `convert_to_customer` idempotency-via-guard shape),
        not by this method."""
        existing = self.get_for_call(workspace_id, call_id)
        payload = {
            "workspace_id": str(workspace_id),
            "call_id": str(call_id),
            "requested_by_member_id": requested_by_member_id,
            "status": "pending",
            "error_message": None,
            "requested_at": datetime.now(timezone.utc).isoformat(),
        }
        try:
            if existing is None:
                response = self._client.table("ai_call_insights").insert(payload).execute()
            else:
                response = (
                    self._client.table("ai_call_insights")
                    .update(payload)
                    .eq("workspace_id", str(workspace_id))
                    .eq("call_id", str(call_id))
                    .execute()
                )
        except APIError as e:
            raise ConflictError(f"Could not request AI analysis: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not request AI analysis for this call.")
        return response.data[0]

    def update_for_call(self, workspace_id: UUID, call_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        response = (
            self._client.table("ai_call_insights")
            .update(data)
            .eq("workspace_id", str(workspace_id))
            .eq("call_id", str(call_id))
            .execute()
        )
        if not response.data:
            raise NotFoundError(f"AI insight for call {call_id} not found.")
        return response.data[0]

    def list_for_calls(self, workspace_id: UUID, call_ids: list[str]) -> dict[str, dict[str, Any]]:
        """call_id -> its insight row, for a batch of calls (Phase 20's
        lead-insights aggregation) — same N+1-avoidance shape as
        LeadRepository.list_names/MemberRepository.map_names."""
        ids = [i for i in call_ids if i]
        if not ids:
            return {}
        response = (
            self._client.table("ai_call_insights")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .in_("call_id", ids)
            .execute()
        )
        return {row["call_id"]: row for row in (response.data or [])}
