from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.leads import MemberSummary

# Note: there is deliberately no separate "CustomerOut" schema here.
# Phase 8 §"Customer model" reuses `leads` (a customer is simply a lead
# with is_customer=true) — GET /customers/{id} returns the existing
# LeadOut shape (backend/app/schemas/leads.py) unchanged, which already
# covers every field Phase 8 §2 "Customer Profile" asks for (name,
# phone, email, status, priority, source, assignment, created/updated).


class DocumentOut(BaseModel):
    """Metadata only — matches `lead_documents`
    (supabase/migrations/000008_leads.sql: "Metadata only — file bytes
    live in Supabase Storage"). Phase 8 §"Documents" only asks to
    *display* documents, not redesign storage, so this deliberately
    omits `storage_path`/`storage_bucket`: generating a signed download
    URL is a later Documents phase's job, not Customer 360's (see
    DocumentRepository's docstring)."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    file_name: str
    mime_type: str | None = None
    size_bytes: int | None = None
    uploaded_by_member: MemberSummary | None = None
    created_at: datetime


class DocumentListResponse(BaseModel):
    items: list[DocumentOut]
    total: int
    limit: int
    offset: int


class TimelineItemOut(BaseModel):
    """One entry of the unified Customer 360 timeline (Phase 8 §3/§4).
    `id` is prefixed by source table (e.g. "call:<uuid>",
    "document:<uuid>") since items are merged from multiple tables and a
    bare row id is not unique across them. `type` reuses the exact
    vocabulary `interactions.type` already defines
    (call/note/status_change/document/follow_up/message/allocation —
    supabase/migrations/000010_allocations_interactions.sql) for every
    source, not just literal `interactions` rows, so the client has one
    consistent type enum regardless of which table an item came from."""

    model_config = ConfigDict(extra="ignore")

    id: str
    type: str
    occurred_at: datetime
    actor_member: MemberSummary | None = None
    summary: str
    details: dict


class TimelineResponse(BaseModel):
    items: list[TimelineItemOut]
    total: int
    limit: int
    offset: int


class NoteCreate(BaseModel):
    """Phase 8 §7's minimum note-creation capability — a note IS an
    `interactions` row with type='note' (docs/architecture/database.md
    §5), so this only carries the note body."""

    text: str = Field(min_length=1, max_length=2000)
