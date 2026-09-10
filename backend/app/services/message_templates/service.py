from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ValidationError
from app.repositories.message_templates import MessageTemplateRepository


class MessageTemplateService:
    """Phase 21A — WhatsApp Message Templates. Deliberately thin: this
    is workspace-scoped reference data (§7 "Do not create a generic
    CMS/template engine"), not a feature with its own business rules —
    the one thing this layer adds over the repository is resolving the
    caller's own member id server-side for `created_by_member_id` (never
    client-supplied, same rule as every other actor-identity field in
    this codebase since Phase 21's hardening pass). `{{variable}}`
    substitution itself is intentionally NOT done here — Flutter already
    has every value a template variable needs (the lead's own name/
    phone/company/status/assigned rep, all already on-screen) with no
    new data to fetch, so rendering happens client-side
    (mobile/lib/features/whatsapp/), not as a network round-trip for
    something the client can do instantly and offline.
    """

    def __init__(self, client: Client):
        self._client = client
        self._templates = MessageTemplateRepository(client)

    def list_templates(self, workspace_id: UUID) -> list[dict[str, Any]]:
        return self._templates.list_for_workspace(workspace_id)

    def create_template(self, workspace_id: UUID, *, name: str, body: str) -> dict[str, Any]:
        actor_id = self._current_member_id(workspace_id)
        return self._templates.create(workspace_id, name=name, body=body, created_by_member_id=actor_id)

    def update_template(self, workspace_id: UUID, template_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        return self._templates.update(workspace_id, template_id, data)

    def delete_template(self, workspace_id: UUID, template_id: UUID) -> None:
        self._templates.delete(workspace_id, template_id)

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id
