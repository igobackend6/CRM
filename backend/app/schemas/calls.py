from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.leads import LeadSummary, MemberSummary

_DIRECTIONS = {"inbound", "outbound"}


def _validate_direction(value: str) -> str:
    if value not in _DIRECTIONS:
        raise ValueError(f"direction must be one of {sorted(_DIRECTIONS)}")
    return value


class CallOutcomeOut(BaseModel):
    """Mirrors `call_outcomes` (supabase/migrations/000007_leads_pipeline_config.sql)
    — workspace-configurable, never hardcoded client-side (Phase 9 §5)."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str
    code: str
    is_positive: bool
    is_default: bool = False


class CallCreate(BaseModel):
    """Phase 9 §4 minimum fields. `workspace_id`/`agent_member_id` are
    deliberately absent — always resolved server-side via
    current_member_id(), never trusted from the client (§4/§9).

    `duration_seconds` is NOT a raw insert into `calls.duration_seconds`
    (that column is Postgres GENERATED ALWAYS, computed from
    connected_at/ended_at — supabase/migrations/000009_calls_followups.sql
    — inserting into it directly is rejected by the database, and this
    schema doesn't invent a client-writable substitute for it). Instead
    CallService derives connected_at/ended_at from started_at + this
    value, so the schema's own generated column still computes the
    authoritative duration — it can never disagree with the timestamps
    that produced it, exactly as the table comment intends. Omitted or
    zero means the call never connected (e.g. no answer): connected_at/
    ended_at stay null and so does duration_seconds.

    No `state` field: manual/backfilled call logs (this endpoint) always
    resolve to the schema's 'ENDED' terminal state server-side — the
    finer-grained result (connected, no answer, busy, interested, ...)
    is what `outcome_id` (call_outcomes, §5) is for. The DIALING/RINGING/
    CONNECTED live-call states are for a real telephony integration
    (out of scope this phase, §12), not a log entered after the fact."""

    lead_id: UUID
    direction: str
    outcome_id: UUID | None = None
    started_at: datetime | None = None
    duration_seconds: int | None = Field(default=None, ge=0)
    notes: str | None = Field(default=None, max_length=2000)

    _check_direction = field_validator("direction")(_validate_direction)


class CallOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    workspace_id: UUID
    lead: LeadSummary
    agent_member: MemberSummary | None = None
    direction: str
    state: str
    outcome: CallOutcomeOut | None = None
    started_at: datetime
    connected_at: datetime | None = None
    ended_at: datetime | None = None
    # Generated column (see CallCreate's docstring) — always present when
    # the call actually connected, always null otherwise. Read-only.
    duration_seconds: int | None = None
    notes: str | None = None
    created_at: datetime


class CallListResponse(BaseModel):
    items: list[CallOut]
    total: int
    limit: int
    offset: int
