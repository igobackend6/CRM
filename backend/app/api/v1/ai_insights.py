from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from supabase import Client

from app.api.dependencies import require_permission
from app.schemas.ai_insights import AIAssistantAnswer, AIAssistantQuestion, AICallInsightOut
from app.security.permissions import Permission
from app.services.ai import AIAssistantService, AIInsightService

# Nested under /workspaces/{workspace_id}/... same as every other
# feature router. No new permission anywhere on this router: viewing/
# requesting a call's AI insight reuses calls.read/calls.update (the
# same gate GET/PATCH .../calls/{id} already use — analyzing a call is
# a property of that call, not a new permission domain), and the lead
# insights/assistant routes reuse leads.read (the same gate
# list_lead_calls/list_lead_follow_ups already use in api/v1/leads.py).
router = APIRouter(tags=["ai"])


def _insight_service(client: Client) -> AIInsightService:
    return AIInsightService(client)


def _assistant_service(client: Client) -> AIAssistantService:
    return AIAssistantService(client)


@router.get("/workspaces/{workspace_id}/calls/{call_id}/ai-insight", response_model=AICallInsightOut | None)
async def get_call_ai_insight(
    workspace_id: UUID,
    call_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.CALLS_READ))],
) -> AICallInsightOut | None:
    """`null` means analysis was never requested for this call — the
    client shows an "Analyze this call" action, not an error."""
    insight = _insight_service(client).get_insight(workspace_id, call_id)
    return AICallInsightOut(**insight) if insight is not None else None


@router.post("/workspaces/{workspace_id}/calls/{call_id}/ai-insight", response_model=AICallInsightOut)
async def request_call_ai_insight(
    workspace_id: UUID,
    call_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.CALLS_UPDATE))],
) -> AICallInsightOut:
    """Always 200s with the resulting insight row — including a
    `status='failed'` row with a clear `error_message` when this
    environment's known Phase 20 prerequisites (a real recording, a
    configured AI provider) aren't met, rather than a 5xx (see
    AIInsightService's own docstring)."""
    return AICallInsightOut(**_insight_service(client).request_analysis(workspace_id, call_id))


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/ai-insights", response_model=list[AICallInsightOut])
async def list_lead_ai_insights(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> list[AICallInsightOut]:
    """Phase 20 §"Lead Insights" — every AI insight row across this
    lead's own calls, newest call first. Gated on leads.read, matching
    `list_lead_calls`/`list_lead_follow_ups` above (a property of a lead
    the caller can already see); `ai_call_insights` RLS additionally
    scopes each individual row to calls the caller could see anyway."""
    rows = _insight_service(client).list_lead_insights(workspace_id, lead_id)
    return [AICallInsightOut(**r) for r in rows]


@router.post("/workspaces/{workspace_id}/leads/{lead_id}/ai-assistant", response_model=AIAssistantAnswer)
async def ask_lead_ai_assistant(
    workspace_id: UUID,
    lead_id: UUID,
    body: AIAssistantQuestion,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> AIAssistantAnswer:
    """Phase 20 §"AI Assistant" — see AIAssistantService's own docstring
    for the full authorization/data-minimization guarantee. Gated on
    leads.read: this is a read-only Q&A over one lead's own already-
    visible data, never a write, never a second lead."""
    return AIAssistantAnswer(**_assistant_service(client).ask(workspace_id, lead_id, body.question))
