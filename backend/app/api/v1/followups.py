from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.api.dependencies import require_permission
from app.schemas.followups import FollowUpCreate, FollowUpListResponse, FollowUpOut, FollowUpUpdate
from app.security.permissions import Permission
from app.services.followups import FollowUpService

# Nested under /workspaces/{workspace_id}/... same as leads.py — every
# route resolves workspace_id from the path only after
# require_permission()'s has_permission() RPC has validated it against
# real membership/role rows (Phase 7 §3/§5's "never trust
# workspace_id/created_by/assigned_member_id from the client").
router = APIRouter(tags=["followups"])


def _service(client: Client) -> FollowUpService:
    return FollowUpService(client)


@router.get("/workspaces/{workspace_id}/follow-ups", response_model=FollowUpListResponse)
async def list_follow_ups(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.FOLLOWUPS_READ))],
    lead_id: UUID | None = Query(default=None),
    status: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> FollowUpListResponse:
    items, total = _service(client).list_follow_ups(workspace_id, lead_id=lead_id, status=status, limit=limit, offset=offset)
    return FollowUpListResponse(items=items, total=total, limit=limit, offset=offset)


@router.get("/workspaces/{workspace_id}/follow-ups/{follow_up_id}", response_model=FollowUpOut)
async def get_follow_up(
    workspace_id: UUID,
    follow_up_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.FOLLOWUPS_READ))],
) -> FollowUpOut:
    return _service(client).get_follow_up(workspace_id, follow_up_id)


@router.post("/workspaces/{workspace_id}/follow-ups", response_model=FollowUpOut, status_code=201)
async def create_follow_up(
    workspace_id: UUID,
    body: FollowUpCreate,
    client: Annotated[Client, Depends(require_permission(Permission.FOLLOWUPS_CREATE))],
) -> FollowUpOut:
    return _service(client).create_follow_up(workspace_id, body.model_dump())


@router.patch("/workspaces/{workspace_id}/follow-ups/{follow_up_id}", response_model=FollowUpOut)
async def update_follow_up(
    workspace_id: UUID,
    follow_up_id: UUID,
    body: FollowUpUpdate,
    client: Annotated[Client, Depends(require_permission(Permission.FOLLOWUPS_UPDATE))],
) -> FollowUpOut:
    """Edit, reschedule, reassign, and complete/cancel (Phase 7 §2D/§2E)
    all go through this one PATCH — see FollowUpService.update_follow_up
    for why that's safe (RLS pins reassignment to managers-or-self
    regardless of what this layer does). No DELETE endpoint: follow_ups
    has no DELETE RLS policy at all (000014_rls_policies.sql) — the
    schema's own documented way to remove a follow-up from view is
    status = 'cancelled', which this endpoint already supports."""
    return _service(client).update_follow_up(workspace_id, follow_up_id, body.model_dump(exclude_unset=True))
