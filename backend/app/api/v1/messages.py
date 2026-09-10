from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.api.dependencies import require_permission
from app.schemas.messaging import (
    ConversationListResponse,
    ConversationOut,
    MessageCreate,
    MessageListResponse,
    MessageOut,
)
from app.security.permissions import Permission
from app.services.messaging import MessagingService

# Phase 16 — Internal CRM Messaging & Conversation Foundation. Nested
# under /workspaces/{workspace_id}/... same as every other feature router
# (calls.py/followups.py/notifications.py) — workspace_id is only ever
# used after require_permission()'s has_permission() RPC has validated it
# against real membership/role rows.
#
# No dedicated messages.read/messages.create permission (§"Security":
# "prefer an existing permission if appropriate... do NOT add
# permissions unnecessarily"): messaging is lead-scoped activity, the
# same way Customer 360's note-creation reuses leads.read/leads.update
# rather than a new permission domain (see api/v1/customers.py). Reads
# are gated on leads.read; the one genuine write (sending a message) on
# leads.update, matching create_customer_note/create_lead_note exactly.
router = APIRouter(tags=["messaging"])


def _service(client: Client) -> MessagingService:
    return MessagingService(client)


@router.get("/workspaces/{workspace_id}/conversations", response_model=ConversationListResponse)
async def list_conversations(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> ConversationListResponse:
    items, total = _service(client).list_conversations(workspace_id, limit=limit, offset=offset)
    return ConversationListResponse(items=items, total=total, limit=limit, offset=offset)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/conversation", response_model=ConversationOut)
async def get_lead_conversation(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> ConversationOut:
    """Get-or-create (§"Lead conversation") — idempotent from the
    caller's point of view (always the one conversation for this lead),
    so it's a GET despite creating a row on first access; the database's
    own `unique (workspace_id, lead_id)` constraint is what actually
    prevents a duplicate, not this endpoint's shape."""
    return _service(client).get_or_create_conversation(workspace_id, lead_id)


@router.get(
    "/workspaces/{workspace_id}/conversations/{conversation_id}/messages",
    response_model=MessageListResponse,
)
async def list_messages(
    workspace_id: UUID,
    conversation_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
    limit: int = Query(default=30, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> MessageListResponse:
    items, total = _service(client).list_messages(workspace_id, conversation_id, limit=limit, offset=offset)
    return MessageListResponse(items=items, total=total, limit=limit, offset=offset)


@router.post(
    "/workspaces/{workspace_id}/conversations/{conversation_id}/messages",
    response_model=MessageOut,
    status_code=201,
)
async def send_message(
    workspace_id: UUID,
    conversation_id: UUID,
    body: MessageCreate,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_UPDATE))],
) -> MessageOut:
    return _service(client).send_message(workspace_id, conversation_id, body.body)


@router.post("/workspaces/{workspace_id}/conversations/{conversation_id}/read")
async def mark_conversation_read(
    workspace_id: UUID,
    conversation_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> dict:
    updated = _service(client).mark_conversation_read(workspace_id, conversation_id)
    return {"updated": updated}
