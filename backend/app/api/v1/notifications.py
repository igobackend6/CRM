from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query

from supabase import Client

from app.api.dependencies import require_permission
from app.schemas.notifications import NotificationListResponse, NotificationMarkReadUpdate, NotificationOut
from app.security.permissions import Permission
from app.services.notifications import NotificationService

# Nested under /workspaces/{workspace_id}/... same as calls.py/followups.py
# — every route resolves workspace_id from the path only after
# require_permission()'s has_permission() RPC has validated it against
# real membership/role rows. `notifications.read` (000013_reference_data.sql)
# is granted to every role, so every active member can read/mark-read
# their own inbox — the "own" part is enforced independently by
# NotificationService resolving the recipient as current_member_id()
# server-side (never the client) and by RLS's notifications_select/
# notifications_mark_read policies underneath.
router = APIRouter(tags=["notifications"])


def _service(client: Client) -> NotificationService:
    return NotificationService(client)


@router.get("/workspaces/{workspace_id}/notifications", response_model=NotificationListResponse)
async def list_notifications(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.NOTIFICATIONS_READ))],
    is_read: bool | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> NotificationListResponse:
    items, total = _service(client).list_notifications(workspace_id, is_read=is_read, limit=limit, offset=offset)
    return NotificationListResponse(items=items, total=total, limit=limit, offset=offset)


@router.get("/workspaces/{workspace_id}/notifications/{notification_id}", response_model=NotificationOut)
async def get_notification(
    workspace_id: UUID,
    notification_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.NOTIFICATIONS_READ))],
) -> NotificationOut:
    return _service(client).get_notification(workspace_id, notification_id)


@router.patch("/workspaces/{workspace_id}/notifications/{notification_id}", response_model=NotificationOut)
async def mark_notification_read(
    workspace_id: UUID,
    notification_id: UUID,
    body: NotificationMarkReadUpdate,
    client: Annotated[Client, Depends(require_permission(Permission.NOTIFICATIONS_READ))],
) -> NotificationOut:
    """Mark one notification read or unread (§1). Only `is_read` is
    accepted — matches the `prevent_notification_content_edit` trigger,
    which already rejects any other column changing on UPDATE, and the
    `notifications_mark_read` RLS policy, which only lets a member touch
    their own notifications regardless of what this layer does."""
    return _service(client).mark_read(workspace_id, notification_id, is_read=body.is_read)


@router.post("/workspaces/{workspace_id}/notifications/mark-all-read")
async def mark_all_notifications_read(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.NOTIFICATIONS_READ))],
) -> dict:
    updated = _service(client).mark_all_read(workspace_id)
    return {"updated": updated}
