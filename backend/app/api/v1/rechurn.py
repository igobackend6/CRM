from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.api.dependencies import require_permission
from app.schemas.rechurn import RechurnQueueResponse
from app.security.permissions import Permission
from app.services.rechurn import RechurnService
from app.services.rechurn.service import DEFAULT_INACTIVE_DAYS

# Nested under /workspaces/{workspace_id}/... same as every other feature
# router. Gated on leads.read — the queue is a read view over leads a
# permitted member can already list/see in the pipeline (same gate
# `list_leads`/`get_pipeline` in api/v1/leads.py use), not a new
# permission domain. There is deliberately no separate "rechurn action"
# endpoint here: calling, logging an outcome, changing status, and
# scheduling/rescheduling a follow-up from the queue all reuse the
# existing calls/leads/follow-ups endpoints unchanged (POST
# /calls, PATCH /leads/{id}/status, POST and PATCH /follow-ups) — see
# RechurnService's own docstring.
router = APIRouter(tags=["rechurn"])


@router.get("/workspaces/{workspace_id}/rechurn", response_model=RechurnQueueResponse)
async def get_rechurn_queue(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
    segment: str | None = Query(default=None, pattern="^(inactive|lost)$"),
    inactive_days: int = Query(default=DEFAULT_INACTIVE_DAYS, ge=1, le=365),
    assigned_member_id: UUID | None = Query(default=None),
    priority: str | None = Query(default=None, max_length=20),
    status_id: UUID | None = Query(default=None),
    source_id: UUID | None = Query(default=None),
    search: str | None = Query(default=None, max_length=200),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> RechurnQueueResponse:
    """`segment` omitted returns the union of both identification
    criteria (Phase 19's "inactive OR previously lost"); `inactive`/
    `lost` narrow to just one. `inactive_days` is the configurable
    inactivity threshold (§"Support ... configurable inactivity
    threshold"), defaulting to `DEFAULT_INACTIVE_DAYS`."""
    items, total = RechurnService(client).list_queue(
        workspace_id,
        segment=segment,
        inactive_days=inactive_days,
        assigned_member_id=assigned_member_id,
        priority=priority,
        status_id=status_id,
        source_id=source_id,
        search=search,
        limit=limit,
        offset=offset,
    )
    return RechurnQueueResponse(items=items, total=total, limit=limit, offset=offset)
