from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class AICallInsightOut(BaseModel):
    """Mirrors `ai_call_insights` (Phase 20 —
    supabase/migrations/000020_ai_call_insights.sql). `status` is always
    one of pending/processing/completed/failed; every AI-derived field
    (transcript/summary/sentiment/action_items/call_score) is null/empty
    until `status == 'completed'` — the client renders by `status`, not
    by guessing from which fields happen to be populated."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    call_id: UUID
    status: str
    provider: str | None = None
    transcript: str | None = None
    summary: str | None = None
    sentiment: str | None = None
    action_items: list[str] = []
    call_score: int | None = None
    error_message: str | None = None
    requested_at: datetime
    completed_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class AIAssistantQuestion(BaseModel):
    question: str = Field(min_length=1, max_length=2000)


class AIAssistantAnswer(BaseModel):
    """`available=False` (with `answer=None`) is the honest, expected
    response in any environment with no AI provider configured
    (§"Never generate fake production AI output") — the client renders
    `message` as the reason, not an error page."""

    available: bool
    answer: str | None = None
    message: str | None = None
