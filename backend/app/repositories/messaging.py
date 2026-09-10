from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.repositories.base import BaseRepository


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class ConversationRepository(BaseRepository):
    """`conversations` (supabase/migrations/000019_messaging.sql) — one
    row per (workspace, lead), enforced by a unique constraint at the
    database level (see get_or_create_for_lead's caller,
    MessagingService.get_or_create_conversation, for the duplicate-safe
    read-then-insert flow)."""

    table_name = "conversations"

    def get_for_lead(self, workspace_id: UUID, lead_id: UUID) -> dict[str, Any] | None:
        response = (
            self._client.table("conversations")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .maybe_single()
            .execute()
        )
        return response.data if response else None

    def get_for_workspace(self, workspace_id: UUID, conversation_id: UUID) -> dict[str, Any]:
        response = (
            self._client.table("conversations")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(conversation_id))
            .maybe_single()
            .execute()
        )
        if response is None or response.data is None:
            # Same message whether missing or hidden by RLS (a lead from
            # another workspace, or a lead this member can't see) — same
            # "don't let a caller distinguish not-found from
            # not-permitted" rule as every other *_for_workspace getter.
            raise NotFoundError(f"Conversation {conversation_id} not found.")
        return response.data

    def create_for_lead(self, workspace_id: UUID, lead_id: UUID, *, created_by_member_id: str) -> dict[str, Any]:
        payload = {
            "workspace_id": str(workspace_id),
            "lead_id": str(lead_id),
            "created_by_member_id": created_by_member_id,
        }
        try:
            response = self._client.table("conversations").insert(payload).execute()
        except APIError as e:
            raise ConflictError(f"Could not create the conversation: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not create the conversation.")
        return response.data[0]

    def list_for_workspace(self, workspace_id: UUID, *, limit: int, offset: int) -> tuple[list[dict[str, Any]], int]:
        response = (
            self._client.table("conversations")
            .select("*", count="exact")
            .eq("workspace_id", str(workspace_id))
            .order("updated_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
        return response.data or [], response.count or 0

    def touch(self, workspace_id: UUID, conversation_id: UUID) -> None:
        """Bumps `updated_at` (the `conversations_set_updated_at` trigger
        always stamps the real `now()`, regardless of the value sent —
        see 000002_functions_generic.sql — so the exact value here
        doesn't matter) so the conversation list's own
        `order by updated_at desc` reflects "most recently active first"
        (§"Conversation List... latest message time") without a second
        aggregation query. Called right after a message is inserted."""
        self._client.table("conversations").update({"updated_at": _now_iso()}).eq("workspace_id", str(workspace_id)).eq(
            "id", str(conversation_id)
        ).execute()


class MessageRepository(BaseRepository):
    """`messages` (supabase/migrations/000019_messaging.sql)."""

    table_name = "messages"

    def list_for_conversation(
        self, workspace_id: UUID, conversation_id: UUID, *, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        """Oldest-first (§"Message API": "paginated oldest/newest-compatible
        message history") — offset 0 is the start of the conversation, so a
        client can page forward through history in reading order without
        re-deriving an offset from a reverse-ordered list."""
        response = (
            self._client.table("messages")
            .select("*", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("conversation_id", str(conversation_id))
            .order("created_at")
            .range(offset, offset + limit - 1)
            .execute()
        )
        return response.data or [], response.count or 0

    def list_recent_for_conversation(self, workspace_id: UUID, conversation_id: UUID, *, limit: int = 20) -> list[dict[str, Any]]:
        """Newest-first, bounded window — feeds
        CustomerService._assemble_activity's Phase 16 message source,
        mirroring CallRepository.list_recent_for_lead exactly."""
        response = (
            self._client.table("messages")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .eq("conversation_id", str(conversation_id))
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_for_conversation(self, workspace_id: UUID, conversation_id: UUID) -> int:
        response = (
            self._client.table("messages")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("conversation_id", str(conversation_id))
            .limit(1)
            .execute()
        )
        return response.count or 0

    def create_for_conversation(
        self, workspace_id: UUID, conversation_id: UUID, *, sender_member_id: str, body: str
    ) -> dict[str, Any]:
        payload = {
            "workspace_id": str(workspace_id),
            "conversation_id": str(conversation_id),
            "sender_member_id": sender_member_id,
            "body": body,
        }
        try:
            response = self._client.table("messages").insert(payload).execute()
        except APIError as e:
            raise ValidationError(f"Could not send the message: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not send the message.")
        return response.data[0]

    def list_latest_and_unread(
        self, workspace_id: UUID, conversation_ids: list[str], *, current_member_id: str
    ) -> tuple[dict[str, dict[str, Any]], dict[str, int]]:
        """One batched query covering both the conversation list's latest-
        message preview and its unread count (§9 "avoid N+1... batch
        related data") — not two separate lookups. Fetches every message
        row for the given conversation ids (bounded to this one
        workspace-scoped `.in_()` set, ordered newest-first) and reduces
        it in Python: the first row seen per conversation_id is its
        latest message (order by created_at desc), and unread_count is
        how many of that conversation's rows have read_at is null and
        were not sent by the caller (their own messages are never
        "unread" to them). A conversation with genuinely heavy message
        volume could return a large result set here — acceptable for
        this phase's scope (internal CRM messaging, not high-volume
        chat); a future phase could replace this with a dedicated SQL
        view/RPC if that ever becomes a real bottleneck."""
        ids = [str(i) for i in conversation_ids if i]
        if not ids:
            return {}, {}
        response = (
            self._client.table("messages")
            .select("id, conversation_id, sender_member_id, body, created_at, read_at")
            .eq("workspace_id", str(workspace_id))
            .in_("conversation_id", ids)
            .order("created_at", desc=True)
            .execute()
        )
        latest: dict[str, dict[str, Any]] = {}
        unread: dict[str, int] = {}
        for row in response.data or []:
            conversation_id = row["conversation_id"]
            if conversation_id not in latest:
                latest[conversation_id] = row
            if row.get("read_at") is None and row.get("sender_member_id") != current_member_id:
                unread[conversation_id] = unread.get(conversation_id, 0) + 1
        return latest, unread

    def mark_conversation_read(self, workspace_id: UUID, conversation_id: UUID, *, current_member_id: str) -> int:
        """Simplest safe read-state implementation (§"Read state": "if the
        existing schema cannot support per-member read state correctly,
        use the simplest safe implementation and document the
        limitation" — see the migration's table comment on `messages`).
        Stamps `read_at` on every currently-unread message in this
        conversation that the caller did NOT send — never their own
        messages, which have nothing to "read". Returns how many rows
        were updated."""
        response = (
            self._client.table("messages")
            .update({"read_at": _now_iso()})
            .eq("workspace_id", str(workspace_id))
            .eq("conversation_id", str(conversation_id))
            .neq("sender_member_id", current_member_id)
            .is_("read_at", "null")
            .execute()
        )
        return len(response.data or [])
