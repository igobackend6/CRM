from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ValidationError
from app.core.logging import get_logger
from app.repositories.ai_insights import AIInsightRepository
from app.repositories.calls import CallRepository
from app.repositories.lead_reference import InteractionRepository
from app.repositories.leads import LeadRepository
from app.services.ai.provider import AIProvider, get_ai_provider
from app.services.notifications import notify

logger = get_logger(__name__)

_NO_RECORDING_MESSAGE = (
    "No call recording is available for this call yet. Call Recording has "
    "not been implemented in this environment (see the Phase 20 completion "
    "report's dependency note) — AI analysis needs an actual recording to "
    "transcribe."
)
_NO_PROVIDER_MESSAGE = (
    "No AI provider is configured for this workspace. An administrator must "
    "configure one (see backend/app/services/ai/provider.py) before AI "
    "analysis can run."
)

# Sentinel distinguishing "caller didn't pass `provider` at all" (resolve
# via get_ai_provider(), the production path) from "caller explicitly
# passed provider=None" (also treated as unavailable, but distinctly —
# used by tests that want to assert the exact "no provider" branch
# without depending on this environment's real configuration).
_UNSET = object()


class AIInsightService:
    """Phase 20 — AI Call Insights. Orchestrates the existing
    Call/Lead/Interaction repositories plus the new, dedicated
    `ai_call_insights` table (see its own migration docstring) into one
    read-only view (`get_insight`/`list_lead_insights`) and one write
    action (`request_analysis`). Same division of responsibility as
    every other service in this codebase: authorization is never decided
    here — the caller (a route, via api/dependencies.py) has already
    enforced calls.read/calls.update before any method here runs, and
    RLS's own ai_call_insights_select/_insert/_update policies
    (000020_ai_call_insights.sql, mirroring calls_select/_update
    exactly) independently scope which rows actually come back or can
    be written.

    IMPORTANT DEPENDENCY: this pipeline is wired end-to-end (transcribe
    -> summarize -> sentiment -> action items -> score -> CRM timeline
    entry -> notification) and fully unit-tested against an injected
    fake provider, but in THIS repository `calls` has no recording
    reference and no AI provider is configured
    (services/ai/provider.get_ai_provider() always returns `None`
    today) — so every real `request_analysis` call in this environment
    deterministically resolves to `status='failed'` with a clear
    `error_message`, never a fabricated transcript/summary/score.
    """

    def __init__(self, client: Client, *, provider: AIProvider | None = _UNSET):  # type: ignore[assignment]
        self._client = client
        self._calls = CallRepository(client)
        self._leads = LeadRepository(client)
        self._insights = AIInsightRepository(client)
        self._interactions = InteractionRepository(client)
        # `provider` left unset (the default) resolves via
        # get_ai_provider() — i.e. None, until Phase 20's prerequisites
        # are met. A test injects a fake provider explicitly; production
        # code never passes this argument.
        self._provider = get_ai_provider() if provider is _UNSET else provider

    # ---- reads ----

    def get_insight(self, workspace_id: UUID, call_id: UUID) -> dict[str, Any] | None:
        self._calls.get_for_workspace(workspace_id, call_id)  # 404s if missing/not visible
        return self._insights.get_for_call(workspace_id, call_id)

    def list_lead_insights(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        """Phase 20 §"Lead Insights" — every one of this lead's calls'
        own AI insight rows, newest call first. Pure query composition
        over existing `calls` + the new `ai_call_insights` table
        (§"Do not create a separate lead database") — no new
        aggregation table, no duplicated lead/customer identity."""
        self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible
        calls = self._calls.list_recent_for_lead(workspace_id, lead_id, limit=50)
        call_ids = [c["id"] for c in calls]
        insights_by_call = self._insights.list_for_calls(workspace_id, call_ids)
        # Only calls that actually have an insight row (i.e. analysis
        # was requested at least once) are returned — a call nobody
        # ever asked to analyze contributes nothing here.
        return [insights_by_call[c["id"]] for c in calls if c["id"] in insights_by_call]

    # ---- write ----

    def request_analysis(self, workspace_id: UUID, call_id: UUID) -> dict[str, Any]:
        """Idempotent-safe like Phase 18's `convert_to_customer`: an
        analysis already `pending`/`processing` is returned unchanged
        rather than started a second time concurrently. A `completed`/
        `failed` row CAN be re-requested (e.g. retrying a transient
        provider failure), which resets it to `pending` first."""
        call = self._calls.get_for_workspace(workspace_id, call_id)  # 404s if missing/not visible
        actor_id = self._current_member_id(workspace_id)

        existing = self._insights.get_for_call(workspace_id, call_id)
        if existing is not None and existing["status"] in ("pending", "processing"):
            return existing

        row = self._insights.upsert_pending(workspace_id, call_id, requested_by_member_id=actor_id)
        return self._run_pipeline(workspace_id, call, row, actor_id=actor_id)

    # ---- pipeline ----

    def _run_pipeline(self, workspace_id: UUID, call: dict[str, Any], row: dict[str, Any], *, actor_id: str) -> dict[str, Any]:
        call_id = row["call_id"]

        # `calls` has no recording reference column at all yet (see this
        # service's own docstring) — `.get(...)` is always None against
        # real Postgres today; a test can still exercise the rest of the
        # pipeline by injecting a fake call row that includes this key.
        recording_ref = call.get("recording_url")
        if not recording_ref:
            return self._fail(workspace_id, call_id, _NO_RECORDING_MESSAGE)
        if self._provider is None:
            return self._fail(workspace_id, call_id, _NO_PROVIDER_MESSAGE)

        try:
            self._insights.update_for_call(workspace_id, call_id, {"status": "processing"})
            transcript = self._provider.transcribe(audio_ref=recording_ref)
            summary = self._provider.summarize(transcript=transcript)
            sentiment = self._provider.analyze_sentiment(transcript=transcript)
            action_items = self._provider.extract_action_items(transcript=transcript)
            score = self._provider.score_call(transcript=transcript)
        except Exception as e:  # noqa: BLE001 - any provider failure is a recorded, recoverable failure, never a crash
            logger.warning("AI analysis failed for call %s: %s", call_id, e)
            return self._fail(workspace_id, call_id, f"AI analysis failed: {e}")

        now = datetime.now(timezone.utc).isoformat()
        updated = self._insights.update_for_call(
            workspace_id,
            call_id,
            {
                "status": "completed",
                "transcript": transcript,
                "summary": summary,
                "sentiment": sentiment,
                "action_items": action_items,
                "call_score": score,
                "completed_at": now,
                "error_message": None,
            },
        )
        self._record_timeline_entry(workspace_id, call, updated, actor_id=actor_id)
        self._notify_ready(workspace_id, call, actor_id=actor_id)
        return updated

    def _fail(self, workspace_id: UUID, call_id: str, message: str) -> dict[str, Any]:
        return self._insights.update_for_call(workspace_id, call_id, {"status": "failed", "error_message": message})

    def _record_timeline_entry(self, workspace_id: UUID, call: dict[str, Any], insight: dict[str, Any], *, actor_id: str) -> None:
        """Reuses the existing `interactions` timeline (`type='note'` —
        the same value Customer 360/Lead Activity's own notes feature
        uses; see interactions' table comment) rather than a new
        activity table or type. References the original call's lead —
        never creates a second call row (§"AI timeline entries should
        reference the original call rather than creating duplicate
        calls")."""
        self._interactions.create_note(
            workspace_id,
            call["lead_id"],
            actor_member_id=actor_id,
            text=f"AI call summary: {insight['summary']}",
        )

    def _notify_ready(self, workspace_id: UUID, call: dict[str, Any], *, actor_id: str) -> None:
        agent_id = call.get("agent_member_id")
        if not agent_id or agent_id == actor_id:
            return  # no point notifying yourself of your own action
        lead_names = self._leads.list_names(workspace_id, [call["lead_id"]])
        notify(
            workspace_id,
            recipient_member_id=agent_id,
            type="system",
            title="AI call summary ready",
            body=lead_names.get(call["lead_id"]),
            related_entity_type="call",
            related_entity_id=str(call["id"]),
        )

    # ---- helpers ----

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id
