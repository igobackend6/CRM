from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.leads import LeadSummary, MemberSummary


class ConversationOut(BaseModel):
    """One row of the conversation list (§"Conversation API": "include
    enough data for UI... lead id, lead name, latest message preview,
    latest message time, unread count") — reuses `LeadSummary` rather
    than a second lead-shape type, same as `CallOut`."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    workspace_id: UUID
    lead: LeadSummary
    latest_message_preview: str | None = None
    latest_message_at: datetime | None = None
    unread_count: int = 0
    created_at: datetime
    updated_at: datetime


class ConversationListResponse(BaseModel):
    items: list[ConversationOut]
    total: int
    limit: int
    offset: int


class MessageCreate(BaseModel):
    """§"Message API"/"Send message": `workspace_id`/sender/timestamps are
    deliberately absent — always resolved server-side (never trusted
    from the client, same rule `CallCreate` follows for
    agent_member_id). `body` rejects empty/whitespace-only text at the
    schema layer (§"empty message rejection") and caps length at 4000
    chars, matching the database's own CHECK constraint
    (000019_messaging.sql) so a bad request 422s here instead of falling
    through to a raw Postgres constraint-violation error."""

    body: str = Field(min_length=1, max_length=4000)

    @field_validator("body")
    @classmethod
    def _reject_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("body must not be empty or whitespace-only")
        return value


class MessageOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    workspace_id: UUID
    conversation_id: UUID
    sender_member: MemberSummary
    body: str
    created_at: datetime
    read_at: datetime | None = None


class MessageListResponse(BaseModel):
    items: list[MessageOut]
    total: int
    limit: int
    offset: int
