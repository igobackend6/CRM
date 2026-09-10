from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

_PRIORITIES = {"low", "medium", "high", "urgent"}


def _validate_priority(value: str | None) -> str | None:
    if value is not None and value not in _PRIORITIES:
        raise ValueError(f"priority must be one of {sorted(_PRIORITIES)}")
    return value


class LeadStatusOut(BaseModel):
    """Mirrors `lead_statuses` (000007 + 000026_lead_status_stage.sql).
    Workspace-configurable name/code/order; `stage` is the fixed
    four-value pipeline bucket (start | in_progress | closed_won |
    closed_lost) that replaced the is_won/is_lost boolean pair.
    """

    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str
    code: str
    sort_order: int
    stage: str
    is_default: bool


class LeadSourceOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str
    code: str
    is_default: bool


class TagOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str
    color: str | None = None


class TagCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    color: str | None = None


class LeadTagAttach(BaseModel):
    tag_id: UUID


class MemberSummary(BaseModel):
    """Display-only identity of a workspace member. Never used for
    authorization decisions — those are re-derived from the database on
    every request (see security/authorization.py)."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    full_name: str | None = None


class LeadSummary(BaseModel):
    """Display-only lead identity — used where a related record (a
    follow-up, Phase 7) needs to show which lead it belongs to without
    pulling in the full LeadOut shape (status/source/tags/etc. the
    caller doesn't need there)."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str


class LeadCreate(BaseModel):
    """Phase 5 §3 minimum fields. `assigned_member_id`/`created_by_member_id`
    are deliberately absent here: the server always resolves both to the
    caller's own workspace_members.id (via the `current_member_id` DB RPC),
    never trusting a client-supplied member id (Phase 5 §9)."""

    name: str = Field(min_length=1, max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = Field(default=None, max_length=254)
    source_id: UUID | None = None
    # Optional: the service resolves the workspace's default status when
    # omitted, since `leads.status_id` is NOT NULL in the schema.
    status_id: UUID | None = None
    priority: str = "medium"
    # {field_code: value} for workspace-defined custom fields
    # (000025_custom_fields.sql). Validated and type-coerced server-side
    # against each field's definition; mandatory fields are enforced on
    # create. Omit entirely if the workspace has no custom fields.
    custom_fields: dict[str, Any] | None = None

    _check_priority = field_validator("priority")(_validate_priority)


class LeadUpdate(BaseModel):
    """All fields optional (PATCH semantics). No `assigned_member_id` —
    see Phase 5 completion report for why lead reassignment is out of
    scope for this phase (display-only for now)."""

    name: str | None = Field(default=None, min_length=1, max_length=200)
    phone: str | None = None
    email: str | None = None
    source_id: UUID | None = None
    status_id: UUID | None = None
    priority: str | None = None
    # Partial: only the codes present are written. A value of null clears
    # that field. Mandatory fields are not re-checked on update.
    custom_fields: dict[str, Any] | None = None

    _check_priority = field_validator("priority")(_validate_priority)


class LeadOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    workspace_id: UUID
    name: str
    phone: str | None = None
    email: str | None = None
    priority: str
    status: LeadStatusOut | None = None
    source: LeadSourceOut | None = None
    assigned_member: MemberSummary | None = None
    created_by_member: MemberSummary | None = None
    is_customer: bool
    # Phase 18 — set alongside is_customer at conversion time
    # (000008_leads.sql's leads_converted_at_requires_customer check);
    # None for a lead that has never been converted.
    converted_at: datetime | None = None
    tags: list[TagOut] = []
    # {field_code: value} for this lead's custom-field values. Empty when
    # the workspace defines no custom fields or none are set on the lead.
    custom_fields: dict[str, Any] = {}
    created_at: datetime
    updated_at: datetime


class LeadListResponse(BaseModel):
    items: list[LeadOut]
    total: int
    limit: int
    offset: int


class InteractionOut(BaseModel):
    """Read-only Customer 360 timeline entry (Phase 5 §2 "Basic interaction
    history"). Nothing in Phase 5 writes to `interactions` — creating
    calls/notes/follow-ups is explicitly out of scope (§17)."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    type: str
    payload: dict
    actor_member: MemberSummary | None = None
    created_at: datetime
