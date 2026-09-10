from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.base import BaseRepository

# Postgres unique_violation — raised by `message_templates_workspace_name_idx`
# (supabase/migrations/000022_message_templates.sql) when a workspace
# already has a template with the same name (case-insensitive).
_UNIQUE_VIOLATION = "23505"


class MessageTemplateRepository(BaseRepository):
    """`message_templates` (supabase/migrations/000022_message_templates.sql)
    — reusable, workspace-scoped WhatsApp/CRM message templates. Simple,
    flat CRUD; there is no soft-delete here (unlike `lead_documents`) —
    a template is pure configuration with no downstream references
    (nothing stores "which template a message came from," per Phase
    21A §"Do NOT implement... message delivery tracking"), so a real
    DELETE is safe and matches `message_templates_delete` RLS."""

    table_name = "message_templates"

    def list_for_workspace(self, workspace_id: UUID) -> list[dict[str, Any]]:
        response = (
            self._client.table("message_templates")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .order("name")
            .execute()
        )
        return response.data or []

    def create(
        self, workspace_id: UUID, *, name: str, body: str, created_by_member_id: UUID | None
    ) -> dict[str, Any]:
        row = {
            "workspace_id": str(workspace_id),
            "name": name,
            "body": body,
            "created_by_member_id": str(created_by_member_id) if created_by_member_id else None,
        }
        try:
            response = self._client.table("message_templates").insert(row).execute()
        except APIError as exc:
            if getattr(exc, "code", None) == _UNIQUE_VIOLATION:
                raise ConflictError(f"A template named '{name}' already exists in this workspace.") from exc
            raise
        return response.data[0]

    def update(self, workspace_id: UUID, template_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        try:
            response = (
                self._client.table("message_templates")
                .update(data)
                .eq("workspace_id", str(workspace_id))
                .eq("id", str(template_id))
                .execute()
            )
        except APIError as exc:
            if getattr(exc, "code", None) == _UNIQUE_VIOLATION:
                raise ConflictError(f"A template named '{data.get('name')}' already exists in this workspace.") from exc
            raise
        if not response.data:
            raise NotFoundError(f"Message template {template_id} not found.")
        return response.data[0]

    def delete(self, workspace_id: UUID, template_id: UUID) -> None:
        response = (
            self._client.table("message_templates")
            .delete()
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(template_id))
            .execute()
        )
        if not response.data:
            raise NotFoundError(f"Message template {template_id} not found.")
