from typing import Annotated, Any

from fastapi import APIRouter, Header, HTTPException

from app.core.config import get_settings
from app.core.logging import get_logger
from app.services.push import push_to_member

logger = get_logger(__name__)

# Server-to-server only. Not under /api/v1 and not JWT-gated — it's
# reached by a Supabase Database Webhook, which authenticates with the
# shared `internal_webhook_secret`. When that setting is unset the whole
# router 404s (the webhook path is simply not enabled).
router = APIRouter(prefix="/internal", tags=["internal"])


def _require_secret(secret: str | None) -> None:
    configured = get_settings().internal_webhook_secret
    if not configured:
        raise HTTPException(status_code=404, detail="Not found")
    if secret != configured:
        raise HTTPException(status_code=401, detail="Bad webhook secret")


@router.post("/push/notification", status_code=202)
async def dispatch_push_for_notification(
    payload: dict[str, Any],
    x_webhook_secret: Annotated[str | None, Header()] = None,
) -> dict[str, str]:
    """Target for a Supabase Database Webhook on `notifications` INSERT.
    Sends the OS-level push for a notification row that was written by
    the database (the on_lead_assignment trigger, or any future
    trigger/edge-function) — i.e. the paths the FastAPI backend never
    sees, chiefly an assignment made from the Admin panel's direct
    `UPDATE leads`.

    Expects Supabase's webhook shape: `{ "type": "INSERT", "record": {…} }`.
    Fire-and-forget: always 202, never blocks the DB write, never
    retries here (the webhook config owns retry policy).
    """
    _require_secret(x_webhook_secret)

    record = payload.get("record") or {}
    workspace_id = record.get("workspace_id")
    recipient = record.get("recipient_member_id")
    if not workspace_id or not recipient:
        logger.warning("Webhook payload missing workspace_id/recipient_member_id; ignoring")
        return {"status": "ignored"}

    push_to_member(
        workspace_id,
        recipient,
        title=record.get("title") or "New notification",
        body=record.get("body"),
        data={
            "notification_id": record.get("id", ""),
            "type": record.get("type", ""),
            "entity_type": record.get("related_entity_type") or "",
            "entity_id": str(record.get("related_entity_id") or ""),
        },
    )
    return {"status": "dispatched"}
