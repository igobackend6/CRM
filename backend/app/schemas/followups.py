from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.leads import LeadSummary, MemberSummary

_TYPES = {"call", "meeting", "task"}
_STATUSES = {"pending", "completed", "cancelled"}


def _validate_type(value: str | None) -> str | None:
    if value is not None and value not in _TYPES:
        raise ValueError(f"type must be one of {sorted(_TYPES)}")
    return value


def _validate_status(value: str | None) -> str | None:
    if value is not None and value not in _STATUSES:
        raise ValueError(f"status must be one of {sorted(_STATUSES)}")
    return value


class FollowUpCreate(BaseModel):
    """Phase 7 §2C minimum fields. `created_by_member_id` is deliberately
    absent — always resolved server-side via current_member_id() (§3/§9),
    same rule as LeadCreate. `assigned_member_id` IS accepted here (unlike
    LeadCreate's owner field) because follow_ups.assigned_member_id is
    NOT NULL — something must be supplied, and the schema's own
    follow_ups_insert RLS policy already lets any member with
    followups.create assign to any active workspace member (managers
    delegating work, or a rep covering for a colleague), not just
    themselves — see FollowUpService.create_follow_up's docstring. When
    omitted, the service defaults it to the creator (self-assign)."""

    lead_id: UUID
    due_at: datetime
    type: str = "task"
    notes: str | None = Field(default=None, max_length=2000)
    assigned_member_id: UUID | None = None

    _check_type = field_validator("type")(_validate_type)


class FollowUpUpdate(BaseModel):
    """All fields optional (PATCH semantics) — covers edit, reschedule
    (due_at), reassignment, and status transitions (§2D/§2E) through one
    endpoint, matching the Phase 7 §4 minimum API surface. `completed_at`/
    `cancelled_at` are never accepted from the client — the service
    derives them from `status` (see service.py)."""

    due_at: datetime | None = None
    type: str | None = None
    notes: str | None = Field(default=None, max_length=2000)
    assigned_member_id: UUID | None = None
    status: str | None = None

    _check_type = field_validator("type")(_validate_type)
    _check_status = field_validator("status")(_validate_status)


class FollowUpOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    workspace_id: UUID
    lead: LeadSummary
    type: str
    due_at: datetime
    status: str
    notes: str | None = None
    assigned_member: MemberSummary | None = None
    created_by_member: MemberSummary | None = None
    completed_at: datetime | None = None
    cancelled_at: datetime | None = None
    # Derived, not stored (mirrors the table comment in
    # 000009_calls_followups.sql: "'Overdue' is intentionally not a
    # stored status ... derived at query time"). Computed the same way
    # here: status == 'pending' and due_at < now().
    is_overdue: bool = False
    created_at: datetime
    updated_at: datetime


class FollowUpListResponse(BaseModel):
    items: list[FollowUpOut]
    total: int
    limit: int
    offset: int
