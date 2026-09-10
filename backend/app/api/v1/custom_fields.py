from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from supabase import Client

from app.api.dependencies import require_permission, require_workspace_member
from app.schemas.custom_fields import CustomFieldCreate, CustomFieldOut, CustomFieldUpdate
from app.security.permissions import Permission
from app.services.custom_fields import CustomFieldService

# Phase 0 (Admin/App alignment) — Custom Lead Fields.
# Read is gated on plain workspace membership (the mobile app needs the
# definitions to render its lead form — same rule as lead-statuses/
# lead-sources/tags/message-templates). Writes are gated on
# `workspace.manage` (admin pipeline configuration), matching the
# custom_fields RLS in 000025_custom_fields.sql.
router = APIRouter(tags=["custom-fields"])


def _service(client: Client) -> CustomFieldService:
    return CustomFieldService(client)


@router.get("/workspaces/{workspace_id}/custom-fields", response_model=list[CustomFieldOut])
async def list_custom_fields(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> list[CustomFieldOut]:
    """Every custom field for the workspace, in sort order — the mobile
    app renders its lead form from this."""
    return _service(client).list_fields(workspace_id)


@router.post("/workspaces/{workspace_id}/custom-fields", response_model=CustomFieldOut, status_code=201)
async def create_custom_field(
    workspace_id: UUID,
    body: CustomFieldCreate,
    client: Annotated[Client, Depends(require_permission(Permission.WORKSPACE_MANAGE))],
) -> CustomFieldOut:
    return _service(client).create_field(workspace_id, body.model_dump())


@router.patch("/workspaces/{workspace_id}/custom-fields/{field_id}", response_model=CustomFieldOut)
async def update_custom_field(
    workspace_id: UUID,
    field_id: UUID,
    body: CustomFieldUpdate,
    client: Annotated[Client, Depends(require_permission(Permission.WORKSPACE_MANAGE))],
) -> CustomFieldOut:
    return _service(client).update_field(workspace_id, field_id, body.model_dump(exclude_unset=True))


@router.delete("/workspaces/{workspace_id}/custom-fields/{field_id}", status_code=204)
async def delete_custom_field(
    workspace_id: UUID,
    field_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.WORKSPACE_MANAGE))],
) -> None:
    """Hard delete — cascades to every stored value for this field."""
    _service(client).delete_field(workspace_id, field_id)
