from datetime import datetime
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import NotFoundError, ValidationError
from app.core.timeparse import parse_supabase_datetime
from app.repositories.allocations import AllocationRepository
from app.repositories.calls import CallRepository
from app.repositories.documents import DocumentRepository
from app.repositories.followups import FollowUpRepository
from app.repositories.lead_reference import InteractionRepository, MemberRepository
from app.repositories.leads import LeadRepository
from app.repositories.messaging import ConversationRepository, MessageRepository
from app.services.followups.service import FollowUpService
from app.services.leads.service import LeadService

_parse = parse_supabase_datetime


class CustomerService:
    """Phase 8 — Customer 360 & Unified Interaction Timeline.

    Deliberately NOT a new "customers" table/repository: a customer is an
    existing `leads` row with `is_customer = true`
    (supabase/migrations/000008_leads.sql's own docstring explains why a
    separate table was rejected). This service is a thin orchestration
    layer over the *existing* Phase 5/6/7 repositories/services — it adds
    exactly one new rule on top of them (a "customer" must satisfy
    is_customer) plus the timeline aggregation §3/§10 needs, which no
    existing service provides. Same non-negotiable as every other
    service in this codebase: authorization is never decided here — a
    route (via api/dependencies.py) has already enforced membership/
    permission through the database RPCs before any method here runs;
    this class only assembles data through a request-scoped,
    user-authenticated `Client`, so RLS still applies underneath
    regardless.
    """

    def __init__(self, client: Client):
        self._client = client
        self._leads = LeadRepository(client)
        self._lead_service = LeadService(client)
        self._follow_ups = FollowUpRepository(client)
        self._follow_up_service = FollowUpService(client)
        self._interactions = InteractionRepository(client)
        self._allocations = AllocationRepository(client)
        self._calls = CallRepository(client)
        self._documents = DocumentRepository(client)
        self._members = MemberRepository(client)
        self._conversations = ConversationRepository(client)
        self._messages = MessageRepository(client)

    # ---- customer profile (§2) ----

    def get_customer(self, workspace_id: UUID, customer_id: UUID) -> dict[str, Any]:
        """Reuses LeadService.get_lead() unchanged (workspace scoping,
        soft-delete exclusion, RLS visibility are all already correct
        there) and adds Phase 8's one extra rule: the lead must actually
        be a customer. A lead that exists and is visible but has
        is_customer=false 404s here — same "customer 360 unavailable"
        semantics as "doesn't exist", matching Phase 8 §8 ("non-customer
        leads get an appropriate alternate state, never silently treated
        as customers") and NotFoundError's own "don't let a caller
        distinguish not-found from not-permitted by probing" philosophy."""
        lead = self._lead_service.get_lead(workspace_id, customer_id)
        self._require_customer(lead)
        return lead

    @staticmethod
    def _require_customer(lead: dict[str, Any]) -> None:
        if not lead.get("is_customer"):
            raise NotFoundError(f"Customer {lead['id']} not found.")

    # ---- documents (§2 "Documents") ----

    def list_documents(
        self, workspace_id: UUID, customer_id: UUID, *, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        self.get_customer(workspace_id, customer_id)  # 404s if missing/not a customer/not visible
        rows, total = self._documents.list_for_lead(workspace_id, customer_id, limit=limit, offset=offset)
        member_ids = {r.get("uploaded_by_member_id") for r in rows}
        member_names = self._members.map_names(workspace_id, [m for m in member_ids if m])
        enriched = []
        for r in rows:
            uploader_id = r.get("uploaded_by_member_id")
            item = dict(r)
            item["uploaded_by_member"] = (
                {"id": uploader_id, "full_name": member_names.get(uploader_id)} if uploader_id else None
            )
            enriched.append(item)
        return enriched, total

    # ---- follow-ups (§2 "Follow-Ups", reuses Phase 7 unchanged) ----

    def list_follow_ups(self, workspace_id: UUID, customer_id: UUID) -> list[dict[str, Any]]:
        self.get_customer(workspace_id, customer_id)  # 404s if missing/not a customer/not visible
        return self._follow_up_service.list_lead_follow_ups(workspace_id, customer_id)

    # ---- notes (§7 — minimum note-creation capability) ----

    def create_note(self, workspace_id: UUID, customer_id: UUID, text: str) -> dict[str, Any]:
        self.get_customer(workspace_id, customer_id)  # 404s if missing/not a customer/not visible
        return self._create_note_row(workspace_id, customer_id, text)

    def create_lead_note(self, workspace_id: UUID, lead_id: UUID, text: str) -> dict[str, Any]:
        """Phase 15 §"Interaction / Note Creation" — the same
        `interactions`-backed note capability as `create_note` above, just
        without Customer 360's `is_customer` requirement, so it also
        works from Lead Detail for a lead that isn't a customer yet. Only
        the visibility check differs; the actual insert is the exact same
        `_create_note_row` helper (one write path, not two)."""
        self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible
        return self._create_note_row(workspace_id, lead_id, text)

    def _create_note_row(self, workspace_id: UUID, lead_id: UUID, text: str) -> dict[str, Any]:
        actor_id = self._current_member_id(workspace_id)
        row = self._interactions.create_note(workspace_id, lead_id, actor_member_id=actor_id, text=text)
        item = dict(row)
        item["actor_member"] = {"id": actor_id, "full_name": self._members.map_names(workspace_id, [actor_id]).get(actor_id)}
        return item

    # ---- unified timeline / activity feed (§3/§4/§10, extended Phase 15) ----

    def get_timeline(
        self, workspace_id: UUID, customer_id: UUID, *, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        self.get_customer(workspace_id, customer_id)  # 404s if missing/not a customer/not visible
        return self._assemble_activity(workspace_id, customer_id, limit=limit, offset=offset)

    def get_lead_activity(
        self, workspace_id: UUID, lead_id: UUID, *, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        """Phase 15 §"Backend" — the same unified activity feed as
        `get_timeline`, generalized to any lead (not just customers), for
        the Lead Detail screen. Reuses `_assemble_activity` verbatim — one
        aggregation implementation for both surfaces, per §"reuse existing
        timeline aggregation logic where possible" / "one source of truth
        for activity data"."""
        self._leads.get_for_workspace(workspace_id, lead_id)  # 404s if missing/not visible
        return self._assemble_activity(workspace_id, lead_id, limit=limit, offset=offset)

    def _assemble_activity(
        self, workspace_id: UUID, lead_id: UUID, *, limit: int, offset: int
    ) -> tuple[list[dict[str, Any]], int]:
        """Assembles one chronologically-ordered, paginated timeline from
        six existing tables (interactions/calls/follow_ups/
        lead_documents/allocations/messages) — no new "timeline"/
        "activities" table, no manufactured records: an item only
        appears if a real row exists (§3/§4). `status_change` is part of
        the interaction-type vocabulary but never populated by this
        phase (see this module's package docstring and the Phase 8
        report's "Known limitations" — no code writes it yet).
        `message` interactions are likewise never written (Phase 16
        §"Activity integration": reads the `messages` table directly
        below instead of duplicating message bodies into `interactions`
        — same "read the source table directly" pattern calls/
        follow_ups/documents/allocations already use here).

        Multi-source pagination strategy (§10 "no N+1", "backend
        aggregation", avoiding "fetching every table independently from
        Flutter and merging client-side"): PostgREST has no server-side
        UNION across tables, so this fetches each source's newest
        `offset + limit` rows (a small, bounded window — NOT "all
        interactions/all documents", §15), merges them in Python, sorts
        once by `occurred_at` descending, and slices to the requested
        page. This is correct (the true global top-K of a merge of
        sorted streams is always a subset of the union of each stream's
        own top-K) and bounded to exactly 6 count queries + 6 windowed
        list queries per request, regardless of how many timeline items
        exist in total — a fixed number of queries, not one per item.
        The messages source additionally needs a conversation lookup
        first (a lead may have no conversation yet — get_for_lead
        returning None just means zero message items, not an error).

        Callers (`get_timeline`/`get_lead_activity`) are responsible for
        their own visibility check first — this method itself does not
        re-check is_customer/workspace visibility, so it must never be
        called directly from a route."""
        window = offset + limit
        interactions = self._interactions.list_for_lead(workspace_id, lead_id, limit=window)
        calls = self._calls.list_recent_for_lead(workspace_id, lead_id, limit=window)
        follow_ups = self._follow_ups.list_recent_for_lead(workspace_id, lead_id, limit=window)
        documents = self._documents.list_recent_for_lead(workspace_id, lead_id, limit=window)
        allocations = self._allocations.list_recent_for_lead(workspace_id, lead_id, limit=window)

        conversation = self._conversations.get_for_lead(workspace_id, lead_id)
        if conversation is None:
            messages: list[dict[str, Any]] = []
            message_count = 0
        else:
            messages = self._messages.list_recent_for_conversation(workspace_id, conversation["id"], limit=window)
            message_count = self._messages.count_for_conversation(workspace_id, conversation["id"])

        total = (
            self._interactions.count_for_lead(workspace_id, lead_id)
            + self._calls.count_for_lead(workspace_id, lead_id)
            + self._follow_ups.count_for_lead(workspace_id, lead_id)
            + self._documents.count_for_lead(workspace_id, lead_id)
            + self._allocations.count_for_lead(workspace_id, lead_id)
            + message_count
        )

        items: list[dict[str, Any]] = []
        items += [self._interaction_item(r) for r in interactions]
        items += [self._call_item(r) for r in calls]
        items += [self._follow_up_item(r) for r in follow_ups]
        items += [self._document_item(r) for r in documents]
        items += [self._allocation_item(r) for r in allocations]
        items += [self._message_item(r) for r in messages]

        # One batched member-name lookup covering both actors and (for
        # allocation items) the assignee, same N+1-avoidance pattern as
        # everywhere else in this codebase (LeadRepository.list_names/
        # MemberRepository.map_names) — still exactly one extra query
        # regardless of how many items/allocations are on this page.
        actor_ids = {i["_actor_id"] for i in items if i.get("_actor_id")}
        assignee_ids = {
            i["details"]["assigned_member_id"]
            for i in items
            if i["type"] == "allocation" and i["details"].get("assigned_member_id")
        }
        member_names = self._members.map_names(workspace_id, list(actor_ids | assignee_ids))
        for item in items:
            actor_id = item.pop("_actor_id", None)
            item["actor_member"] = {"id": actor_id, "full_name": member_names.get(actor_id)} if actor_id else None
            if item["type"] == "allocation":
                assignee_id = item["details"].get("assigned_member_id")
                if assignee_id:
                    # Phase 15 §"Flutter Activity UI": "allocation
                    # assignee when applicable" — the raw id alone isn't
                    # enough for the UI to show a name.
                    item["details"]["assigned_member"] = {"id": assignee_id, "full_name": member_names.get(assignee_id)}

        items.sort(key=lambda i: i["occurred_at"], reverse=True)
        page = items[offset : offset + limit]
        return page, total

    # ---- timeline item builders ----
    # Each returns a dict shaped for TimelineItemOut (id/type/occurred_at/
    # _actor_id (resolved to actor_member above)/summary/details).

    @staticmethod
    def _interaction_item(row: dict[str, Any]) -> dict[str, Any]:
        payload = row.get("payload") or {}
        row_type = row.get("type", "note")
        summary = {
            "note": lambda p: (p.get("text") or "Note")[:140],
            "call": lambda p: "Call logged",
            "status_change": lambda p: "Status changed",
            "document": lambda p: "Document activity",
            "follow_up": lambda p: "Follow-up activity",
            "message": lambda p: "Message",
            "allocation": lambda p: "Assignment activity",
        }.get(row_type, lambda p: row_type.replace("_", " ").title())(payload)
        return {
            "id": f"interaction:{row['id']}",
            "type": row_type,
            "occurred_at": _parse(row["created_at"]),
            "_actor_id": row.get("actor_member_id"),
            "summary": summary,
            "details": payload,
        }

    @staticmethod
    def _call_item(row: dict[str, Any]) -> dict[str, Any]:
        direction = row.get("direction", "outbound")
        state = row.get("state", "ENDED")
        duration = row.get("duration_seconds")
        summary = f"{direction.capitalize()} call — {state.lower()}"
        return {
            "id": f"call:{row['id']}",
            "type": "call",
            "occurred_at": _parse(row["started_at"]),
            "_actor_id": row.get("agent_member_id"),
            "summary": summary,
            "details": {
                "direction": direction,
                "state": state,
                "duration_seconds": duration,
                "notes": row.get("notes"),
            },
        }

    @staticmethod
    def _follow_up_item(row: dict[str, Any]) -> dict[str, Any]:
        summary = f"Follow-up scheduled ({row.get('type', 'task')}) — {row.get('status', 'pending')}"
        return {
            "id": f"follow_up:{row['id']}",
            "type": "follow_up",
            "occurred_at": _parse(row["created_at"]),
            "_actor_id": row.get("created_by_member_id"),
            "summary": summary,
            "details": {
                "follow_up_type": row.get("type"),
                "due_at": row.get("due_at"),
                "status": row.get("status"),
                "notes": row.get("notes"),
            },
        }

    @staticmethod
    def _document_item(row: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": f"document:{row['id']}",
            "type": "document",
            "occurred_at": _parse(row["created_at"]),
            "_actor_id": row.get("uploaded_by_member_id"),
            "summary": f"Document uploaded: {row.get('file_name', 'file')}",
            "details": {
                "file_name": row.get("file_name"),
                "mime_type": row.get("mime_type"),
                "size_bytes": row.get("size_bytes"),
            },
        }

    @staticmethod
    def _message_item(row: dict[str, Any]) -> dict[str, Any]:
        """Phase 16 — reads `messages` directly (see _assemble_activity's
        docstring for why this isn't an `interactions` row)."""
        body = row.get("body") or ""
        return {
            "id": f"message:{row['id']}",
            "type": "message",
            "occurred_at": _parse(row["created_at"]),
            "_actor_id": row.get("sender_member_id"),
            "summary": body[:140],
            "details": {"conversation_id": row.get("conversation_id"), "read_at": row.get("read_at")},
        }

    @staticmethod
    def _allocation_item(row: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": f"allocation:{row['id']}",
            "type": "allocation",
            "occurred_at": _parse(row["assigned_at"]),
            "_actor_id": row.get("assigned_by_member_id"),
            "summary": "Lead assigned",
            "details": {"assigned_member_id": row.get("assigned_member_id"), "status": row.get("status")},
        }

    # ---- helpers ----

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id
