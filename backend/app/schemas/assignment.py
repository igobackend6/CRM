from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.schemas.leads import MemberSummary


class AssignmentRequest(BaseModel):
    """member_id = None means unassign — leads.assigned_member_id is
    nullable (supabase/migrations/000008_leads.sql), so this is a
    schema-supported action, not a workaround. Never trust
    `assigned_by` from the client (Phase 6 §4/§9's rule, carried from
    Phase 5) — the server always resolves it via current_member_id()."""

    member_id: UUID | None = None


class AllocationOut(BaseModel):
    """One row of the read-only assignment history for a lead —
    mirrors `allocations` (000010_allocations_interactions.sql) plus a
    computed `previous_member` (the prior allocation's assignee; not a
    stored column — allocations only records the new assignee per row)."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    previous_member: MemberSummary | None = None
    assigned_member: MemberSummary | None = None
    assigned_by: MemberSummary | None = None
    status: str
    assigned_at: datetime
    created_at: datetime
