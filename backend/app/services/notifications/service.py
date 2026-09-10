from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ValidationError
from app.core.logging import get_logger
from app.core.supabase_client import get_supabase_client
from app.repositories.notifications import NotificationRepository

logger = get_logger(__name__)

# The full set the `notifications.type` CHECK constraint allows
# (000011_notifications_audit.sql). 'followup_reminder'/'followup_overdue'
# are due-date-driven and would need a scheduled/background job to
# populate — explicitly out of scope for Phase 10 ("scheduled reminders",
# "background notification workers"), so this phase never writes them;
# they're listed here only so a future phase adding that job knows the
# schema already has somewhere to put it. 'system' is what Phase 10 uses
# for an event the schema doesn't have a dedicated type for (follow-up
# assignment/reassignment, call activity) rather than inventing a new
# CHECK value for them.
NOTIFICATION_TYPES = {"lead_assigned", "followup_reminder", "followup_overdue", "lead_reassigned", "system"}


class NotificationService:
    """Phase 10 — Notifications & Activity Alerts. Read/mark-read surface
    for api/v1/notifications.py, built with the caller's own
    request-scoped client — same division of responsibility as every
    other service in this codebase (authorization already enforced by
    api/dependencies.py before any method here runs; RLS's
    notifications_select/notifications_mark_read policies still apply
    underneath regardless). Notification *creation* is deliberately not
    a method here — see the module-level `notify()` below, used directly
    by the CRM event hooks (lead assignment, follow-up assignment, call
    activity) instead of round-tripping through this request-scoped
    instance, since it needs the privileged service-role client
    (notifications has no INSERT policy for `authenticated`)."""

    def __init__(self, client: Client):
        self._client = client
        self._notifications = NotificationRepository(client)

    def list_notifications(
        self, workspace_id: UUID, *, is_read: bool | None, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        recipient_member_id = self._current_member_id(workspace_id)
        return self._notifications.list_for_workspace(
            workspace_id, recipient_member_id, is_read=is_read, limit=limit, offset=offset
        )

    def get_notification(self, workspace_id: UUID, notification_id: UUID) -> dict[str, Any]:
        recipient_member_id = self._current_member_id(workspace_id)
        return self._notifications.get_for_workspace(workspace_id, recipient_member_id, notification_id)

    def mark_read(self, workspace_id: UUID, notification_id: UUID, *, is_read: bool) -> dict[str, Any]:
        recipient_member_id = self._current_member_id(workspace_id)
        return self._notifications.mark_read(workspace_id, recipient_member_id, notification_id, is_read=is_read)

    def mark_all_read(self, workspace_id: UUID) -> int:
        recipient_member_id = self._current_member_id(workspace_id)
        return self._notifications.mark_all_read(workspace_id, recipient_member_id)

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id


def notify(
    workspace_id: UUID,
    *,
    recipient_member_id: str,
    type: str,
    title: str,
    body: str | None = None,
    related_entity_type: str | None = None,
    related_entity_id: str | None = None,
) -> None:
    """Minimal, targeted notification creation for the CRM event hooks
    Phase 10 §2 asks for (lead assignment/reassignment, follow-up
    assignment, call activity) — called directly from
    LeadService.assign_lead / FollowUpService.create_follow_up /
    FollowUpService.update_follow_up / CallService.create_call. This is
    intentionally NOT a generic event bus: there is no publish/subscribe
    registry, no notification for every mutation, and every call site
    passes an already-validated recipient (an active member id the
    calling service resolved itself, never a client-supplied id).

    Uses the privileged service-role client
    (core/supabase_client.get_supabase_client) because `notifications`
    has no INSERT policy for `authenticated` at all
    (000014_rls_policies.sql/000011_notifications_audit.sql: only
    backend/service-role code creates notification rows) — a
    request-scoped user client could never perform this insert
    regardless of permissions.

    Never raises: a notification is a side effect of the primary
    operation (assigning a lead, logging a call, ...), not the
    operation itself, so a failure here (missing service-role
    credentials, a transient DB error) is logged and swallowed rather
    than failing the request that triggered it.
    """
    if type not in NOTIFICATION_TYPES:
        logger.error("Refusing to create a notification with an unknown type: %s", type)
        return

    client = get_supabase_client()
    if client is None:
        logger.warning("Service-role client unavailable; skipping notification creation.")
        return

    try:
        NotificationRepository(client).create_for_workspace(
            workspace_id,
            {
                "recipient_member_id": recipient_member_id,
                "type": type,
                "title": title,
                "body": body,
                "related_entity_type": related_entity_type,
                "related_entity_id": related_entity_id,
            },
        )
    except Exception:
        logger.exception("Failed to create a %s notification for workspace %s.", type, workspace_id)
