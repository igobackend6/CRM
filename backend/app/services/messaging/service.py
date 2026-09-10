from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ConflictError, ValidationError
from app.repositories.lead_reference import MemberRepository
from app.repositories.leads import LeadRepository
from app.repositories.messaging import ConversationRepository, MessageRepository
from app.services.notifications import notify


class MessagingService:
    """Phase 16 — Internal CRM Messaging & Conversation Foundation.
    Orchestrates the new `conversations`/`messages` repositories plus the
    existing leads/workspace_members repositories, same division of
    responsibility as every other service here: authorization is already
    enforced by api/dependencies.py before any method here runs; RLS
    (000019_messaging.sql) still applies underneath regardless through
    this request-scoped, user-authenticated `Client`.
    """

    def __init__(self, client: Client):
        self._client = client
        self._conversations = ConversationRepository(client)
        self._messages = MessageRepository(client)
        self._leads = LeadRepository(client)
        self._members = MemberRepository(client)

    # ---- conversations ----

    def get_or_create_conversation(self, workspace_id: UUID, lead_id: UUID) -> dict[str, Any]:
        """§"Lead conversation": return the lead's single conversation,
        creating it on first access. The lead must belong to THIS
        workspace and be visible to the caller (`get_for_workspace`
        404s otherwise — same "never trust a client-supplied id"
        rule every other lead-nested write in this codebase follows).
        Duplicate-safe: the database's `unique (workspace_id, lead_id)`
        constraint (000019_messaging.sql) is the real guarantee against
        two conversations for one lead, not this read-then-insert
        check alone — if a concurrent request wins the race, this
        method recovers by re-reading instead of surfacing the
        constraint violation as an error."""
        self._leads.get_for_workspace(workspace_id, lead_id)
        existing = self._conversations.get_for_lead(workspace_id, lead_id)
        if existing is not None:
            return self._enrich_conversations(workspace_id, [existing])[0]

        creator_id = self._current_member_id(workspace_id)
        try:
            created = self._conversations.create_for_lead(workspace_id, lead_id, created_by_member_id=creator_id)
        except ConflictError:
            created = self._conversations.get_for_lead(workspace_id, lead_id)
            if created is None:
                raise
        return self._enrich_conversations(workspace_id, [created])[0]

    def list_conversations(self, workspace_id: UUID, *, limit: int, offset: int) -> tuple[list[dict[str, Any]], int]:
        rows, total = self._conversations.list_for_workspace(workspace_id, limit=limit, offset=offset)
        return self._enrich_conversations(workspace_id, rows), total

    # ---- messages ----

    def list_messages(
        self, workspace_id: UUID, conversation_id: UUID, *, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        self._conversations.get_for_workspace(workspace_id, conversation_id)  # validates workspace/visibility
        rows, total = self._messages.list_for_conversation(workspace_id, conversation_id, limit=limit, offset=offset)
        return self._enrich_messages(workspace_id, rows), total

    def send_message(self, workspace_id: UUID, conversation_id: UUID, body: str) -> dict[str, Any]:
        """§"Send message": workspace/sender/timestamps are always
        server-derived — `sender_member_id` is only ever
        `current_member_id()`, never taken from the request (MessageCreate
        has no such field to begin with). `conversation_id` is validated
        as a real, visible conversation in THIS workspace before anything
        is inserted (`get_for_workspace` 404s otherwise) — the composite
        FK on messages.conversation_id already makes a cross-workspace
        reference structurally impossible either way; this is
        defense-in-depth plus a clean 404, same reasoning as
        CallService.create_call.

        Phase 16 §"Activity integration": deliberately does NOT insert an
        `interactions` row (that would duplicate the message body into a
        second table — §"do not duplicate message content into multiple
        systems"). Instead CustomerService._assemble_activity reads the
        `messages` table directly as a sixth timeline source, the same
        way it already reads calls/follow_ups/documents/allocations
        directly rather than through `interactions` — one source of
        truth for message content.

        §"Notification integration": reuses the same lead-owner
        recipient semantics Phase 9's CallService.create_call already
        established (the only "recipient" concept this schema has) —
        notifies the lead's assigned member when someone else messages
        about their lead, no new recipient model invented."""
        conversation = self._conversations.get_for_workspace(workspace_id, conversation_id)
        sender_id = self._current_member_id(workspace_id)

        row = self._messages.create_for_conversation(workspace_id, conversation_id, sender_member_id=sender_id, body=body)
        self._conversations.touch(workspace_id, conversation_id)

        lead = self._leads.get_for_workspace(workspace_id, conversation["lead_id"])
        owner_id = lead.get("assigned_member_id")
        if owner_id and owner_id != sender_id:
            notify(
                workspace_id,
                recipient_member_id=owner_id,
                type="system",
                title="New message on your lead",
                body=body[:140],
                related_entity_type="conversation",
                related_entity_id=conversation["id"],
            )

        return self._enrich_messages(workspace_id, [row])[0]

    def mark_conversation_read(self, workspace_id: UUID, conversation_id: UUID) -> int:
        self._conversations.get_for_workspace(workspace_id, conversation_id)
        member_id = self._current_member_id(workspace_id)
        return self._messages.mark_conversation_read(workspace_id, conversation_id, current_member_id=member_id)

    # ---- enrichment (batched — no N+1, §9) ----

    def _enrich_conversations(self, workspace_id: UUID, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not rows:
            return []
        lead_ids = {r["lead_id"] for r in rows}
        lead_names = self._leads.list_names(workspace_id, list(lead_ids))
        current_member_id = self._current_member_id(workspace_id)
        latest, unread = self._messages.list_latest_and_unread(
            workspace_id, [r["id"] for r in rows], current_member_id=current_member_id
        )

        enriched = []
        for r in rows:
            latest_row = latest.get(r["id"])
            item = dict(r)
            item["lead"] = {"id": r["lead_id"], "name": lead_names.get(r["lead_id"], "Unknown lead")}
            item["latest_message_preview"] = (latest_row.get("body") or "")[:140] if latest_row else None
            item["latest_message_at"] = latest_row.get("created_at") if latest_row else None
            item["unread_count"] = unread.get(r["id"], 0)
            enriched.append(item)
        return enriched

    def _enrich_messages(self, workspace_id: UUID, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not rows:
            return []
        sender_ids = {r.get("sender_member_id") for r in rows if r.get("sender_member_id")}
        sender_names = self._members.map_names(workspace_id, list(sender_ids))

        enriched = []
        for r in rows:
            sender_id = r.get("sender_member_id")
            item = dict(r)
            item["sender_member"] = {"id": sender_id, "full_name": sender_names.get(sender_id)}
            enriched.append(item)
        return enriched

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id
