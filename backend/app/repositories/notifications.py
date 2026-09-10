from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.repositories.base import BaseRepository


class NotificationRepository(BaseRepository):
    """`notifications` (supabase/migrations/000011_notifications_audit.sql)
    — a strictly personal inbox: `notifications_select`/`notifications_mark_read`
    (000014_rls_policies.sql) both pin every row to
    `recipient_member_id = current_member_id(workspace_id)`, so the read/
    update methods below still filter on workspace_id explicitly (same
    "never rely on RLS alone" convention as every other *_for_workspace
    repository in this codebase) even though RLS would additionally
    enforce recipient scoping underneath regardless.

    There is deliberately no client-facing INSERT (no INSERT policy for
    `authenticated` at all) — `create_for_workspace` exists only for
    `create_for_workspace`'s caller to use with the privileged
    service-role client (see services/notifications/service.py's
    `notify()`), never with a request-scoped user client.
    """

    table_name = "notifications"

    def list_for_workspace(
        self,
        workspace_id: UUID,
        recipient_member_id: str,
        *,
        is_read: bool | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> tuple[list[dict[str, Any]], int]:
        query = (
            self._client.table("notifications")
            .select("*", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("recipient_member_id", recipient_member_id)
        )
        if is_read is not None:
            query = query.eq("is_read", is_read)
        query = query.order("created_at", desc=True).range(offset, offset + limit - 1)
        response = query.execute()
        return response.data or [], response.count or 0

    def get_for_workspace(self, workspace_id: UUID, recipient_member_id: str, notification_id: UUID) -> dict[str, Any]:
        response = (
            self._client.table("notifications")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("recipient_member_id", recipient_member_id)
            .eq("id", str(notification_id))
            .maybe_single()
            .execute()
        )
        if response is None or response.data is None:
            # Same message whether the row doesn't exist or belongs to a
            # different recipient — matches every other *_for_workspace
            # getter in this codebase (never confirm/deny existence of a
            # row the caller can't see).
            raise NotFoundError(f"Notification {notification_id} not found.")
        return response.data

    def mark_read(
        self, workspace_id: UUID, recipient_member_id: str, notification_id: UUID, *, is_read: bool
    ) -> dict[str, Any]:
        payload = {"is_read": is_read, "read_at": _now_iso() if is_read else None}
        try:
            response = (
                self._client.table("notifications")
                .update(payload)
                .eq("workspace_id", str(workspace_id))
                .eq("recipient_member_id", recipient_member_id)
                .eq("id", str(notification_id))
                .execute()
            )
        except APIError as e:
            raise ValidationError(f"Could not update the notification: {e.message}") from e
        if not response.data:
            raise NotFoundError(f"Notification {notification_id} not found.")
        return response.data[0]

    def mark_all_read(self, workspace_id: UUID, recipient_member_id: str) -> int:
        """A single UPDATE ... WHERE is_read = false statement — "mark
        all read" only needed to be efficiently supported by the existing
        schema (Phase 10 §1), and this is: one round trip, no per-row
        loop, backed by the existing
        `notifications_recipient_unread_idx` (workspace_id,
        recipient_member_id, is_read, created_at desc)."""
        response = (
            self._client.table("notifications")
            .update({"is_read": True, "read_at": _now_iso()})
            .eq("workspace_id", str(workspace_id))
            .eq("recipient_member_id", recipient_member_id)
            .eq("is_read", False)
            .execute()
        )
        return len(response.data or [])

    def create_for_workspace(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        payload = {**data, "workspace_id": str(workspace_id)}
        try:
            response = self._client.table("notifications").insert(payload).execute()
        except APIError as e:
            raise ConflictError(f"Could not create the notification: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not create the notification.")
        return response.data[0]


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
