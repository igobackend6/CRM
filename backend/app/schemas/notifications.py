from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class NotificationOut(BaseModel):
    """Mirrors `notifications` (supabase/migrations/000011_notifications_audit.sql)
    directly — unlike CallOut/FollowUpOut this is not "enriched" with a
    joined lead/member summary: `related_entity_type`/`related_entity_id`
    are an intentionally unconstrained polymorphic reference (the table's
    own comment), so the client resolves a navigation target itself from
    the type+id pair against its own existing routes (Phase 10 §4)
    rather than the backend guessing which of leads/follow_ups/calls/
    customers to join against."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    type: str
    title: str
    body: str | None = None
    related_entity_type: str | None = None
    related_entity_id: UUID | None = None
    is_read: bool
    read_at: datetime | None = None
    created_at: datetime


class NotificationListResponse(BaseModel):
    items: list[NotificationOut]
    total: int
    limit: int
    offset: int


class NotificationMarkReadUpdate(BaseModel):
    """§1 "mark notification read/unread" — the only mutable fields on a
    notification (enforced independently by the `prevent_notification_content_edit`
    trigger, which rejects any other column changing on UPDATE)."""

    is_read: bool
