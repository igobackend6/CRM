from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class DeviceTokenRegister(BaseModel):
    """The mobile app sends this on login and whenever FCM rotates the
    token. `profile_id` is never in the body — it's always the caller's
    own id (device_tokens RLS enforces `profile_id = auth.uid()`)."""

    token: str = Field(min_length=1, max_length=4096)
    platform: Literal["android", "ios", "web"]


class DeviceTokenOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    token: str
    platform: str
    created_at: datetime
    updated_at: datetime
