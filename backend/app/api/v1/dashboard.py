from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.api.dependencies import require_workspace_member
from app.schemas.customer360 import TimelineResponse
from app.schemas.dashboard import DashboardSummaryOut
from app.services.dashboard import DashboardService

# Nested under /workspaces/{workspace_id}/... same as every other feature
# router. Gated on plain workspace membership (require_workspace_member),
# not a specific permission — every role, including team_mate, needs a
# working home-screen dashboard (§"Flutter" — "Integrate Dashboard as the
# authenticated app's main/home screen"), and `reports.read` is NOT
# granted to team_mate (000013_reference_data.sql), so gating on it would
# lock reps out of their own home screen. The underlying data is already
# governed by the existing leads.read/followups.read/calls.read/
# notifications.read permissions (and RLS beneath those regardless), so
# no separate dashboard-specific permission is needed — matches
# list_call_outcomes/list_lead_statuses's existing "plain membership"
# gating for workspace-wide reference reads.
router = APIRouter(tags=["dashboard"])


def _service(client: Client) -> DashboardService:
    return DashboardService(client)


@router.get("/workspaces/{workspace_id}/dashboard/summary", response_model=DashboardSummaryOut)
async def get_dashboard_summary(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    range: str = Query(default="all", pattern="^(all|today|this_week|this_month)$"),
) -> DashboardSummaryOut:
    """`range` (Phase 17 §"Date Range") is optional and defaults to
    `"all"` — omitting it (every pre-Phase-17 client, and every
    pre-Phase-17 test) reproduces the exact Phase 11 response for the
    9 original fields; only the additive Phase 17 fields exist to be
    computed differently per range. Same plain-membership gate as
    before — this is still a read of data the caller can already see,
    not a new capability."""
    return DashboardSummaryOut(**_service(client).get_summary(workspace_id, range_key=range))


@router.get("/workspaces/{workspace_id}/dashboard/recent-activity", response_model=TimelineResponse)
async def get_dashboard_recent_activity(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    limit: int = Query(default=20, ge=1, le=50),
    offset: int = Query(default=0, ge=0),
) -> TimelineResponse:
    """Reuses Phase 8's `TimelineResponse`/`TimelineItemOut` schemas
    unchanged (see app/schemas/dashboard.py's own note) — same shape as
    Customer 360's `GET /customers/{id}/timeline`, just workspace-wide."""
    items, total = _service(client).get_recent_activity(workspace_id, limit=limit, offset=offset)
    return TimelineResponse(items=items, total=total, limit=limit, offset=offset)
