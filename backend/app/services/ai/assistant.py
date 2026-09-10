from typing import Any
from uuid import UUID

from supabase import Client

from app.repositories.ai_insights import AIInsightRepository
from app.repositories.calls import CallRepository
from app.repositories.leads import LeadRepository
from app.services.ai.provider import AIProvider, get_ai_provider
from app.services.ai.service import _UNSET

_UNAVAILABLE_MESSAGE = "The AI assistant is not available yet — no AI provider is configured for this workspace."


class AIAssistantService:
    """Phase 20 §"AI Assistant" — the smallest safe foundation, not a
    general-purpose chatbot: one stateless "ask a question about this
    lead" operation, scoped to exactly one already-authorized lead.

    Every one of the assistant's own required guarantees is structural,
    not a promise the AI layer has to keep:
    1. authenticate the user       -> enforced by api/dependencies.py
       before this class is ever constructed (same as every other
       service in this codebase)
    2. resolve workspace membership -> enforced the same way
    3. enforce existing CRM permissions -> the route gates on
       Permission.LEADS_READ; RLS's own leads_select scopes which lead
       rows are even visible underneath that
    4. retrieve only authorized CRM records -> `_build_context` only
       ever reads the ONE lead this request already validated
       (LeadRepository.get_for_workspace, which 404s otherwise) plus
       that lead's own calls/AI insights — never a second lead, never a
       cross-workspace query, never a raw/unscoped table read
    5. send only authorized/necessary data to the AI provider -> the
       assembled `context` string is the *entire* universe of data the
       provider ever sees; there is no mechanism for the provider to
       request additional data
    6. never expose another workspace's data -> impossible by
       construction: every read here is workspace_id-scoped through the
       caller's own RLS-bound client, identical to every other service

    No conversation history is persisted (no new table) — each call is
    independent, which is what keeps this a "foundation" rather than a
    full assistant architecture (§"If assistant implementation would
    require a large new architecture, defer it and document why" — a
    persisted, multi-turn conversation log is exactly that larger
    architecture, deferred here).
    """

    def __init__(self, client: Client, *, provider: AIProvider | None = _UNSET):  # type: ignore[assignment]
        self._client = client
        self._leads = LeadRepository(client)
        self._calls = CallRepository(client)
        self._insights = AIInsightRepository(client)
        self._provider = get_ai_provider() if provider is _UNSET else provider

    def ask(self, workspace_id: UUID, lead_id: UUID, question: str) -> dict[str, Any]:
        lead = self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible

        if self._provider is None:
            return {"available": False, "answer": None, "message": _UNAVAILABLE_MESSAGE}

        context = self._build_context(workspace_id, lead)
        try:
            answer = self._provider.answer_question(context=context, question=question)
        except Exception as e:  # noqa: BLE001 - a provider failure is a clean "unavailable" answer, never a crash
            return {"available": False, "answer": None, "message": f"The AI assistant could not answer right now: {e}"}
        return {"available": True, "answer": answer, "message": None}

    def _build_context(self, workspace_id: UUID, lead: dict[str, Any]) -> str:
        """The entire, bounded input the provider ever sees — this
        lead's own name/priority/customer-state plus its own calls'
        completed AI summaries. No phone/email (not needed to answer a
        CRM question about the lead's status) and no other lead's data
        at all."""
        lines = [
            f"Lead: {lead.get('name')}",
            f"Priority: {lead.get('priority')}",
            f"Customer: {'yes' if lead.get('is_customer') else 'no'}",
        ]
        calls = self._calls.list_recent_for_lead(workspace_id, str(lead["id"]), limit=10)
        insights = self._insights.list_for_calls(workspace_id, [c["id"] for c in calls])
        for call in calls:
            insight = insights.get(call["id"])
            if insight and insight.get("status") == "completed":
                lines.append(f"Call summary: {insight.get('summary')}")
        return "\n".join(lines)
