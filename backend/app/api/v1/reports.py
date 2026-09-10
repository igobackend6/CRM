from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.api.dependencies import require_permission, require_workspace_member
from app.core.date_ranges import REPORT_DATE_RANGES
from app.schemas.reports import PersonalReportOut, PipelineReportOut, TeamReportOut
from app.security.permissions import Permission
from app.services.reports import ReportService

# Phase 21C — Complete Reports & Analytics. Personal is gated on plain
# workspace membership (require_workspace_member) — every role,
# including team_mate (who never has `reports.read` —
# 000013_reference_data.sql), needs to see their OWN performance, same
# reasoning as api/v1/dashboard.py's own gate. Team/Pipeline are
# workspace-wide views of everyone's data, so they're gated on
# `Permission.REPORTS_READ` (granted to manager/admin/ceo, not
# team_mate) — the permission this codebase already had on the books,
# unused, since Phase 2 (§"Team Reports": "If existing permission rules
# distinguish managers/admins from normal members, enforce them
# consistently").
router = APIRouter(tags=["reports"])

_RANGE_PATTERN = "^(" + "|".join(sorted(REPORT_DATE_RANGES)) + ")$"


def _service(client: Client) -> ReportService:
    return ReportService(client)


@router.get("/workspaces/{workspace_id}/reports/personal", response_model=PersonalReportOut)
async def get_personal_report(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    range: str = Query(default="all_time", pattern=_RANGE_PATTERN),
    since: datetime | None = Query(default=None),
    until: datetime | None = Query(default=None),
) -> PersonalReportOut:
    """`since`/`until` are only consulted when `range=custom` (validated
    inside ReportService/date_ranges.resolve_report_range); a client that
    never uses "custom" never needs to send them."""
    return PersonalReportOut(
        **_service(client).get_personal_report(workspace_id, range_key=range, custom_since=since, custom_until=until)
    )


@router.get("/workspaces/{workspace_id}/reports/team", response_model=TeamReportOut)
async def get_team_report(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.REPORTS_READ))],
    range: str = Query(default="all_time", pattern=_RANGE_PATTERN),
    since: datetime | None = Query(default=None),
    until: datetime | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> TeamReportOut:
    return TeamReportOut(
        **_service(client).get_team_report(
            workspace_id, range_key=range, custom_since=since, custom_until=until, limit=limit, offset=offset
        )
    )


@router.get("/workspaces/{workspace_id}/reports/pipeline", response_model=PipelineReportOut)
async def get_pipeline_report(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.REPORTS_READ))],
    range: str = Query(default="all_time", pattern=_RANGE_PATTERN),
    since: datetime | None = Query(default=None),
    until: datetime | None = Query(default=None),
) -> PipelineReportOut:
    return PipelineReportOut(
        **_service(client).get_pipeline_report(workspace_id, range_key=range, custom_since=since, custom_until=until)
    )
