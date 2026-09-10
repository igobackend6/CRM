from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.base import BaseRepository


class LeadStatusRepository(BaseRepository):
    """Workspace-configurable pipeline stages (Phase 5 §5) — read-only
    from this phase's API surface. Writing statuses is workspace
    administration, out of scope here."""

    table_name = "lead_statuses"

    def list_for_workspace(self, workspace_id: UUID) -> list[dict[str, Any]]:
        response = (
            self._client.table("lead_statuses")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .order("sort_order")
            .execute()
        )
        return response.data or []

    def get_for_workspace(self, workspace_id: UUID, status_id: UUID) -> dict[str, Any] | None:
        """Server-side validation that a client-supplied status_id is real
        and belongs to THIS workspace (Phase 12 §"Security": never trust a
        client-supplied status id) — same shape as
        CallOutcomeRepository.get_for_workspace. The composite FK on
        leads.status_id (workspace_id, status_id) already makes a
        cross-workspace reference structurally impossible; this
        additionally lets the service return a clean 422 instead of
        letting a bad id fall through to a raw Postgres FK-violation
        error."""
        response = (
            self._client.table("lead_statuses")
            .select("id")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(status_id))
            .maybe_single()
            .execute()
        )
        return response.data if response else None


class LeadSourceRepository(BaseRepository):
    table_name = "lead_sources"

    def list_for_workspace(self, workspace_id: UUID) -> list[dict[str, Any]]:
        response = (
            self._client.table("lead_sources")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .order("name")
            .execute()
        )
        return response.data or []

    def get_for_workspace(self, workspace_id: UUID, source_id: UUID) -> dict[str, Any] | None:
        """Server-side validation that a client-supplied source_id belongs
        to THIS workspace (Phase 14 §"Security": validate all filter ids
        against current workspace) — same shape as
        LeadStatusRepository.get_for_workspace."""
        response = (
            self._client.table("lead_sources")
            .select("id")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(source_id))
            .maybe_single()
            .execute()
        )
        return response.data if response else None


class CallOutcomeRepository(BaseRepository):
    """Workspace-configurable call result catalogue (Phase 9 §5) — mirrors
    `LeadStatusRepository` exactly (000007_leads_pipeline_config.sql:
    `call_outcomes` is defined right alongside `lead_statuses`, same
    "configurable, never hardcoded client-side" reasoning). Read-only
    from this phase's API surface — writing outcomes is workspace
    administration, out of scope here, same as lead_statuses/lead_sources."""

    table_name = "call_outcomes"

    def list_for_workspace(self, workspace_id: UUID) -> list[dict[str, Any]]:
        response = (
            self._client.table("call_outcomes")
            .select("*")
            .eq("workspace_id", str(workspace_id))
            .order("name")
            .execute()
        )
        return response.data or []

    def get_for_workspace(self, workspace_id: UUID, outcome_id: UUID) -> dict[str, Any] | None:
        """Server-side validation that a client-supplied outcome_id is
        real and belongs to THIS workspace (Phase 9 §9: never trust
        client input unchecked) — same shape as
        MemberRepository.get_active. The composite FK on
        calls.outcome_id already makes a cross-workspace reference
        structurally impossible; this additionally lets the service
        return a clean 422 instead of letting a bad id fall through to a
        raw Postgres FK-violation error."""
        response = (
            self._client.table("call_outcomes")
            .select("id")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(outcome_id))
            .maybe_single()
            .execute()
        )
        return response.data if response else None

    def map_by_ids(self, workspace_id: UUID, outcome_ids: list[str]) -> dict[str, dict[str, Any]]:
        """id -> outcome row, for enriching a batch of calls without an
        N+1 (Phase 9 §15) — same pattern as MemberRepository.map_names."""
        ids = [i for i in outcome_ids if i]
        if not ids:
            return {}
        response = (
            self._client.table("call_outcomes")
            .select("id, name, code, is_positive, is_default")
            .eq("workspace_id", str(workspace_id))
            .in_("id", ids)
            .execute()
        )
        return {row["id"]: row for row in response.data or []}


class TagRepository(BaseRepository):
    """Phase 5 §6 — any active workspace member may create a tag (matches
    `tags_insert` RLS: `is_workspace_member`, no specific permission
    required)."""

    table_name = "tags"

    def list_for_workspace(self, workspace_id: UUID) -> list[dict[str, Any]]:
        response = (
            self._client.table("tags").select("*").eq("workspace_id", str(workspace_id)).order("name").execute()
        )
        return response.data or []

    def create_for_workspace(self, workspace_id: UUID, data: dict[str, Any]) -> dict[str, Any]:
        payload = {**data, "workspace_id": str(workspace_id)}
        try:
            response = self._client.table("tags").insert(payload).execute()
        except APIError as e:
            raise ConflictError(f"Could not create tag: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not create the tag.")
        return response.data[0]

    def get_for_workspace(self, workspace_id: UUID, tag_id: UUID) -> dict[str, Any] | None:
        """Server-side validation that a client-supplied tag_id belongs to
        THIS workspace (Phase 14 §"Security") — same shape as
        LeadStatusRepository.get_for_workspace."""
        response = (
            self._client.table("tags")
            .select("id")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(tag_id))
            .maybe_single()
            .execute()
        )
        return response.data if response else None


class MemberRepository(BaseRepository):
    """Display-only member lookups (names for "assigned to"/"created by"/
    "activity by" — Phase 5 §2/§10; the assignment picker — Phase 6
    §3). Never used to make an authorization decision; that always goes
    through security/authorization.py. Only ever returns id + full_name
    — no phone/avatar_url — per Phase 6 §3's "do not expose sensitive
    profile information unnecessarily"."""

    table_name = "workspace_members"

    def map_names(self, workspace_id: UUID, member_ids: list[str]) -> dict[str, str | None]:
        ids = [i for i in member_ids if i]
        if not ids:
            return {}
        response = (
            self._client.table("workspace_members")
            # workspace_members has two FKs to profiles (profile_id, and
            # invited_by — 000006_workspace_members_permissions.sql), so
            # PostgREST can't infer which one "profiles" means on its own
            # (PGRST201, "more than one relationship was found for
            # 'workspace_members' and 'profiles'") — a schema-level
            # ambiguity regardless of any row's actual invited_by value,
            # which the FakeSupabaseClient-backed unit tests never
            # exercise (they don't build real PostgREST queries). Naming
            # the real FK constraint disambiguates it to the member's own
            # profile, not who invited them.
            .select("id, profile:profiles!workspace_members_profile_id_fkey(full_name)")
            .eq("workspace_id", str(workspace_id))
            .in_("id", ids)
            .execute()
        )
        result: dict[str, str | None] = {}
        for row in response.data or []:
            profile = row.get("profile") or {}
            result[row["id"]] = profile.get("full_name")
        return result

    def list_active(self, workspace_id: UUID) -> list[dict[str, Any]]:
        """The assignment picker's candidate list (Phase 6 §3) — active
        members of this workspace only. `status` is the schema's
        active/invited/suspended/removed field (000006_workspace_members_permissions.sql)."""
        response = (
            self._client.table("workspace_members")
            # Same profile_id/invited_by ambiguity as map_names() above.
            .select("id, profile:profiles!workspace_members_profile_id_fkey(full_name)")
            .eq("workspace_id", str(workspace_id))
            .eq("status", "active")
            .execute()
        )
        result = []
        for row in response.data or []:
            profile = row.get("profile") or {}
            result.append({"id": row["id"], "full_name": profile.get("full_name")})
        return result

    def get_for_workspace(self, workspace_id: UUID, member_id: UUID) -> dict[str, Any] | None:
        """Server-side validation that a client-supplied
        assigned_member_id filter belongs to THIS workspace (Phase 14
        §"Security") — deliberately not restricted to `status = 'active'`
        like `get_active` below: filtering "leads assigned to X" should
        still work for a member who has since been suspended/removed, the
        same way their name still shows on any lead they're already
        assigned to."""
        response = (
            self._client.table("workspace_members")
            .select("id")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(member_id))
            .maybe_single()
            .execute()
        )
        return response.data if response else None

    def get_active(self, workspace_id: UUID, member_id: UUID) -> dict[str, Any] | None:
        """Server-side validation that a would-be assignee is a real,
        active member of THIS workspace (Phase 6 §4: never trust
        assigned_member_id from the client). The composite FK on
        leads.assigned_member_id already makes a cross-workspace
        reference structurally impossible; this additionally rejects a
        removed/suspended/invited member, which the FK alone doesn't."""
        response = (
            self._client.table("workspace_members")
            .select("id")
            .eq("workspace_id", str(workspace_id))
            .eq("id", str(member_id))
            .eq("status", "active")
            .maybe_single()
            .execute()
        )
        return response.data if response else None


class LeadTagRepository:
    """`lead_tags` is a pure junction table (no surrogate id column worth
    wrapping in BaseRepository), so this is a small standalone repository
    rather than a BaseRepository subclass."""

    def __init__(self, client):
        self._client = client

    def map_tags_for_leads(self, workspace_id: UUID, lead_ids: list[str]) -> dict[str, list[dict[str, Any]]]:
        ids = [str(i) for i in lead_ids]
        if not ids:
            return {}
        response = (
            self._client.table("lead_tags")
            .select("lead_id, tag:tags(id,name,color)")
            .eq("workspace_id", str(workspace_id))
            .in_("lead_id", ids)
            .execute()
        )
        result: dict[str, list[dict[str, Any]]] = {}
        for row in response.data or []:
            if row.get("tag"):
                result.setdefault(row["lead_id"], []).append(row["tag"])
        return result

    def list_for_lead(self, workspace_id: UUID, lead_id: UUID) -> list[dict[str, Any]]:
        response = (
            self._client.table("lead_tags")
            .select("tag:tags(id,name,color)")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .execute()
        )
        return [row["tag"] for row in (response.data or []) if row.get("tag")]

    def list_lead_ids_for_tag(self, workspace_id: UUID, tag_id: UUID) -> list[str]:
        """Phase 14's tag filter: "leads tagged X" resolved as a set of
        lead ids, which LeadService then intersects with the rest of the
        query via `LeadRepository.list_for_workspace`'s `lead_id_in`
        (tags are a many-to-many join, so this can't be a plain `.eq()`
        on `leads` itself)."""
        response = (
            self._client.table("lead_tags")
            .select("lead_id")
            .eq("workspace_id", str(workspace_id))
            .eq("tag_id", str(tag_id))
            .execute()
        )
        return [row["lead_id"] for row in (response.data or [])]

    def attach(self, workspace_id: UUID, lead_id: UUID, tag_id: UUID) -> dict[str, Any]:
        payload = {"workspace_id": str(workspace_id), "lead_id": str(lead_id), "tag_id": str(tag_id)}
        try:
            response = self._client.table("lead_tags").insert(payload).execute()
        except APIError as e:
            raise ConflictError(f"Could not attach tag: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not attach the tag (it may already be attached).")
        return response.data[0]

    def detach(self, workspace_id: UUID, lead_id: UUID, tag_id: UUID) -> None:
        response = (
            self._client.table("lead_tags")
            .delete()
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .eq("tag_id", str(tag_id))
            .execute()
        )
        if not response.data:
            raise NotFoundError("Tag was not attached to this lead.")


class InteractionRepository(BaseRepository):
    """Read-only for Phase 5 (§2 "Basic interaction history") — nothing
    in this phase writes interaction rows; see the STRICTLY OUT OF SCOPE
    list (calls/follow-ups/notes creation are later phases)."""

    table_name = "interactions"

    def list_for_lead(self, workspace_id: UUID, lead_id: UUID, *, limit: int = 50) -> list[dict[str, Any]]:
        response = (
            self._client.table("interactions")
            .select("id, type, payload, actor_member_id, created_at")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_for_lead(self, workspace_id: UUID, lead_id: UUID) -> int:
        """Added in Phase 8 for the unified Customer 360 timeline's
        per-source total (services/customer360/service.py)."""
        response = (
            self._client.table("interactions")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .eq("lead_id", str(lead_id))
            .limit(1)
            .execute()
        )
        return response.count or 0

    def list_recent_for_workspace(self, workspace_id: UUID, *, limit: int = 20) -> list[dict[str, Any]]:
        """Newest-first, bounded window, workspace-wide — added in Phase 11
        for the dashboard's recent-activity feed. Mirrors `list_for_lead`
        minus the lead filter (that method's name predates
        `list_recent_for_lead`-style naming elsewhere in this file, but
        it's already newest-first/bounded, so this only drops the lead
        filter rather than duplicating the whole method)."""
        response = (
            self._client.table("interactions")
            .select("id, type, payload, actor_member_id, created_at")
            .eq("workspace_id", str(workspace_id))
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    def count_for_workspace(self, workspace_id: UUID) -> int:
        response = (
            self._client.table("interactions")
            .select("id", count="exact")
            .eq("workspace_id", str(workspace_id))
            .limit(1)
            .execute()
        )
        return response.count or 0

    def create_note(self, workspace_id: UUID, lead_id: UUID, *, actor_member_id: str, text: str) -> dict[str, Any]:
        """Phase 8 §7: the *minimum* note-creation capability, reusing the
        existing `interactions` model (`type = 'note'`) rather than a new
        notes table — matches docs/architecture/database.md §5 ("Notes").
        `interactions_insert` RLS has no dedicated permission-code check
        (only the same visibility rule as interactions_select); the API
        layer still gates this behind Permission.LEADS_UPDATE (see
        api/v1/customers.py) as a coarser, defense-in-depth pre-check,
        the same pattern already used for lead tag attach/detach."""
        payload = {
            "workspace_id": str(workspace_id),
            "lead_id": str(lead_id),
            "actor_member_id": actor_member_id,
            "type": "note",
            "payload": {"text": text},
        }
        try:
            response = self._client.table("interactions").insert(payload).execute()
        except APIError as e:
            raise ConflictError(f"Could not create the note: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not create the note.")
        return response.data[0]

    def create_status_change(
        self, workspace_id: UUID, lead_id: UUID, *, actor_member_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        """Phase 18 §"Conversion Activity" — records lead lifecycle events
        (currently just conversion) using the existing `type='status_change'`
        value `interactions.type` already allows
        (000010_allocations_interactions.sql) but no earlier phase ever
        wrote (see CustomerService._assemble_activity's docstring: "never
        populated by this phase"). No new table, no new interaction type —
        same insert shape as `create_note` above."""
        row = {
            "workspace_id": str(workspace_id),
            "lead_id": str(lead_id),
            "actor_member_id": actor_member_id,
            "type": "status_change",
            "payload": payload,
        }
        try:
            response = self._client.table("interactions").insert(row).execute()
        except APIError as e:
            raise ConflictError(f"Could not record the status change: {e.message}") from e
        if not response.data:
            raise ConflictError("Could not record the status change.")
        return response.data[0]
