from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.schemas.leads import LeadStatusOut, MemberSummary


class RechurnNextFollowUp(BaseModel):
    """The minimum needed to show "next follow-up" on a rechurn card —
    deliberately narrower than the full `FollowUpOut` (no lead/assignee/
    notes/is_overdue), the same "only what the card needs" restraint
    `PipelineLeadCard` already applies to its own lead shape."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    type: str
    due_at: datetime


class RechurnLeadCard(BaseModel):
    """One rechurn queue row — a non-customer lead flagged as a
    candidate for re-engagement (Phase 19). Deliberately narrower than
    `LeadOut`: no tags/source/created_by, matching `PipelineLeadCard`'s
    own "the board renders many of these at once" reasoning."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str
    phone: str | None = None
    email: str | None = None
    priority: str
    status: LeadStatusOut | None = None
    assigned_member: MemberSummary | None = None
    is_customer: bool
    # `leads.updated_at` — the same "last touched" signal the queue's own
    # inactivity filter is computed from (see LeadRepository's
    # list_rechurn_candidates docstring); not a separate activity-log
    # aggregation.
    last_activity_at: datetime
    next_follow_up: RechurnNextFollowUp | None = None


class RechurnQueueResponse(BaseModel):
    items: list[RechurnLeadCard]
    total: int
    limit: int
    offset: int
