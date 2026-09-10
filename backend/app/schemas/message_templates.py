from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class MessageTemplateOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str
    body: str
    created_at: datetime
    updated_at: datetime


class MessageTemplateCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    body: str = Field(min_length=1, max_length=2000)


class MessageTemplateUpdate(BaseModel):
    """All fields optional (PATCH semantics), matching LeadUpdate's
    convention (schemas/leads.py)."""

    name: str | None = Field(default=None, min_length=1, max_length=100)
    body: str | None = Field(default=None, min_length=1, max_length=2000)
