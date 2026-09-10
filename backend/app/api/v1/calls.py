from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.api.dependencies import require_permission, require_workspace_member
from app.schemas.calls import CallCreate, CallListResponse, CallOut, CallOutcomeOut
from app.security.permissions import Permission
from app.services.calls import CallService

# Nested under /workspaces/{workspace_id}/... same as leads.py/followups.py
# — every route resolves workspace_id from the path only after
# require_permission()'s has_permission() RPC has validated it against
# real membership/role rows (Phase 9 §9's "never trust workspace_id/
# actor from the client"). The lead-nested `GET /leads/{lead_id}/calls`
# lives in leads.py instead, alongside the other lead-nested resources
# (interactions/allocations/follow-ups) — same convention Phase 7/8 used.
router = APIRouter(tags=["calls"])


def _service(client: Client) -> CallService:
    return CallService(client)


@router.get("/workspaces/{workspace_id}/calls", response_model=CallListResponse)
async def list_calls(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.CALLS_READ))],
    lead_id: UUID | None = Query(default=None),
    direction: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> CallListResponse:
    items, total = _service(client).list_calls(workspace_id, lead_id=lead_id, direction=direction, limit=limit, offset=offset)
    return CallListResponse(items=items, total=total, limit=limit, offset=offset)


@router.get("/workspaces/{workspace_id}/calls/{call_id}", response_model=CallOut)
async def get_call(
    workspace_id: UUID,
    call_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.CALLS_READ))],
) -> CallOut:
    return _service(client).get_call(workspace_id, call_id)


@router.post("/workspaces/{workspace_id}/calls", response_model=CallOut, status_code=201)
async def create_call(
    workspace_id: UUID,
    body: CallCreate,
    client: Annotated[Client, Depends(require_permission(Permission.CALLS_CREATE))],
) -> CallOut:
    """Manual call-log creation (§4) — only implemented because
    calls_insert RLS already supports a self-or-manager-scoped insert
    (000014_rls_policies.sql). See CallService.create_call for why
    workspace_id/agent_member_id/state are never taken from the
    request body."""
    return _service(client).create_call(workspace_id, body.model_dump())


@router.get("/workspaces/{workspace_id}/call-outcomes", response_model=list[CallOutcomeOut])
async def list_call_outcomes(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> list[CallOutcomeOut]:
    """§5 — matches list_lead_statuses/list_lead_sources's gating
    (plain membership, not a specific permission): every active member
    needs to see the outcome catalogue to log or read a call."""
    return _service(client).list_outcomes(workspace_id)
