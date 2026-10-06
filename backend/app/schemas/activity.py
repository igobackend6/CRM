from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ActivityReportIn(BaseModel):
    """The body of every "the app is reporting in" call. The schema stores
    no per-user timezone, so the app sends its own UTC offset (minutes, east
    positive: India is 330) and the server uses it to decide which local
    day a moment belongs to."""

    utc_offset_minutes: int = Field(default=0, ge=-840, le=840)


class ActivityStatusOut(BaseModel):
    on_break: bool
    break_started_at: datetime | None = None


class ActivitySummaryOut(ActivityStatusOut):
    """The caller's own totals for one window, in seconds. login = talk +
    ringing + wrap-up + break + idle; see services/activity/calc.py."""

    since: datetime
    until: datetime
    login_seconds: int
    talk_seconds: int
    wrap_up_seconds: int
    break_seconds: int
    idle_seconds: int


class DailyActivityOut(BaseModel):
    """One stored `agent_daily_activity` row."""

    model_config = ConfigDict(extra="ignore")

    member_id: UUID
    day: date
    utc_offset_minutes: int
    login_seconds: int
    talk_seconds: int
    wrap_up_seconds: int
    break_seconds: int
    idle_seconds: int
    updated_at: datetime
