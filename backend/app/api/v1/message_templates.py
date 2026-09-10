from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from supabase import Client

from app.api.dependencies import require_permission, require_workspace_member
from app.schemas.message_templates import MessageTemplateCreate, MessageTemplateOut, MessageTemplateUpdate
from app.security.permissions import Permission
from app.services.message_templates import MessageTemplateService

# Phase 21A — WhatsApp Message Templates. Read is gated on plain
# workspace membership (same as tags/lead-statuses/lead-sources in
# api/v1/leads.py — reference data every member needs to use, not a
# permission-gated resource); writes are gated on the new
# `templates.manage` permission (supabase/migrations/000022_message_templates.sql),
# granted to every seeded role including team_mate — see that
# migration's own comment for why this isn't manager-only.
router = APIRouter(tags=["message-templates"])


def _service(client: Client) -> MessageTemplateService:
    return MessageTemplateService(client)


@router.get("/workspaces/{workspace_id}/message-templates", response_model=list[MessageTemplateOut])
async def list_message_templates(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> list[MessageTemplateOut]:
    return _service(client).list_templates(workspace_id)


@router.post("/workspaces/{workspace_id}/message-templates", response_model=MessageTemplateOut, status_code=201)
async def create_message_template(
    workspace_id: UUID,
    body: MessageTemplateCreate,
    client: Annotated[Client, Depends(require_permission(Permission.TEMPLATES_MANAGE))],
) -> MessageTemplateOut:
    return _service(client).create_template(workspace_id, name=body.name, body=body.body)


@router.patch("/workspaces/{workspace_id}/message-templates/{template_id}", response_model=MessageTemplateOut)
async def update_message_template(
    workspace_id: UUID,
    template_id: UUID,
    body: MessageTemplateUpdate,
    client: Annotated[Client, Depends(require_permission(Permission.TEMPLATES_MANAGE))],
) -> MessageTemplateOut:
    return _service(client).update_template(workspace_id, template_id, body.model_dump(exclude_unset=True))


@router.delete("/workspaces/{workspace_id}/message-templates/{template_id}", status_code=204)
async def delete_message_template(
    workspace_id: UUID,
    template_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.TEMPLATES_MANAGE))],
) -> None:
    _service(client).delete_template(workspace_id, template_id)
