from datetime import date, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body, Depends, Query
from supabase import Client

from app.api.dependencies import require_workspace_member
from app.schemas.activity import ActivityReportIn, ActivityStatusOut, ActivitySummaryOut, DailyActivityOut
from app.services.activity import ActivityService

# Login Analytics. Plain workspace membership is the gate for everything
# here: every role reports its own login/break time and reads its own
# totals. Reading OTHER members' stored daily rows is not a code path in
# this file — it is the `agent_daily_activity` RLS policy (manager-or-above
# see everyone, a member only themselves), the same table the admin panel
# reads directly.
router = APIRouter(tags=["activity"])


def _service(client: Client) -> ActivityService:
    return ActivityService(client)


@router.post("/workspaces/{workspace_id}/activity/heartbeat", response_model=ActivityStatusOut)
async def heartbeat(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    body: Annotated[ActivityReportIn, Body()] = ActivityReportIn(),
) -> ActivityStatusOut:
    """The running app checks in (about once a minute). Foreground or
    background does not matter — only that the app process is alive."""
    return ActivityStatusOut(**_service(client).heartbeat(workspace_id, utc_offset_minutes=body.utc_offset_minutes))


@router.post("/workspaces/{workspace_id}/activity/sign-out", response_model=ActivityStatusOut)
async def sign_out(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    body: Annotated[ActivityReportIn, Body()] = ActivityReportIn(),
) -> ActivityStatusOut:
    return ActivityStatusOut(**_service(client).sign_out(workspace_id, utc_offset_minutes=body.utc_offset_minutes))


@router.post("/workspaces/{workspace_id}/activity/break/start", response_model=ActivityStatusOut)
async def start_break(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    body: Annotated[ActivityReportIn, Body()] = ActivityReportIn(),
) -> ActivityStatusOut:
    return ActivityStatusOut(**_service(client).start_break(workspace_id, utc_offset_minutes=body.utc_offset_minutes))


@router.post("/workspaces/{workspace_id}/activity/break/end", response_model=ActivityStatusOut)
async def end_break(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    body: Annotated[ActivityReportIn, Body()] = ActivityReportIn(),
) -> ActivityStatusOut:
    return ActivityStatusOut(**_service(client).end_break(workspace_id, utc_offset_minutes=body.utc_offset_minutes))


@router.get("/workspaces/{workspace_id}/activity/summary", response_model=ActivitySummaryOut)
async def get_summary(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    since: datetime = Query(...),
    until: datetime = Query(...),
) -> ActivitySummaryOut:
    """The caller's own login / talk / wrap-up / break / idle seconds for
    [since, until), computed fresh (includes the session in progress)."""
    return ActivitySummaryOut(**_service(client).get_summary(workspace_id, since=since, until=until))


@router.get("/workspaces/{workspace_id}/activity/daily", response_model=list[DailyActivityOut])
async def list_daily(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
    since: date = Query(...),
    until: date = Query(...),
    member_id: UUID | None = Query(default=None),
) -> list[DailyActivityOut]:
    """The stored per-day rows for [since, until] inclusive. A member gets
    their own; manager-or-above get every member's (RLS), optionally
    narrowed with `member_id`."""
    rows = _service(client).list_daily(
        workspace_id, since_day=since, until_day=until, member_id=str(member_id) if member_id else None
    )
    return [DailyActivityOut(**row) for row in rows]
