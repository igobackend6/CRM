import re
from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# Kept in sync with the CHECK constraint on custom_fields.field_type
# (supabase/migrations/000025_custom_fields.sql). If they drift, the
# migration wins. These are Runo's five field types verbatim.
_FIELD_TYPES = {"text", "number", "date", "options", "multi_options"}
_CHOICE_TYPES = {"options", "multi_options"}
_CODE_RE = re.compile(r"^[a-z][a-z0-9_]*$")


class CustomFieldOption(BaseModel):
    """One choice for an options / multi_options field. `code` is the
    stable machine key stored in custom_field_values; `label` is what
    the form shows; `sort_order` positions it in the picker."""

    code: str = Field(min_length=1, max_length=100)
    label: str = Field(min_length=1, max_length=200)
    sort_order: int = 0

    @field_validator("code")
    @classmethod
    def _code_is_a_slug(cls, v: str) -> str:
        if not _CODE_RE.match(v):
            raise ValueError("option code must be lowercase letters, digits and underscores, starting with a letter")
        return v


class CustomFieldCreate(BaseModel):
    """Admin defines a field once; the mobile app renders it into the
    lead form on next load. `code` is immutable after creation (values
    reference the field's id, but the code is the client's stable
    lookup key) — so is `field_type` (changing it would invalidate every
    stored value). To change either, create a new field."""

    name: str = Field(min_length=1, max_length=100)
    code: str = Field(min_length=1, max_length=64)
    field_type: str
    options: list[CustomFieldOption] = []
    auto_fill: bool = True
    is_filterable: bool = False
    is_readonly: bool = False
    is_mandatory: bool = False
    sort_order: int = 0

    @field_validator("code")
    @classmethod
    def _code_is_a_slug(cls, v: str) -> str:
        if not _CODE_RE.match(v):
            raise ValueError("code must be lowercase letters, digits and underscores, starting with a letter")
        return v

    @field_validator("field_type")
    @classmethod
    def _known_type(cls, v: str) -> str:
        if v not in _FIELD_TYPES:
            raise ValueError(f"field_type must be one of {sorted(_FIELD_TYPES)}")
        return v

    @model_validator(mode="after")
    def _options_match_type(self) -> "CustomFieldCreate":
        if self.field_type in _CHOICE_TYPES:
            if not self.options:
                raise ValueError(f"{self.field_type} requires at least one option")
            seen = {o.code for o in self.options}
            if len(seen) != len(self.options):
                raise ValueError("option codes must be unique")
        elif self.options:
            raise ValueError(f"{self.field_type} fields take no options")
        return self


class CustomFieldUpdate(BaseModel):
    """PATCH semantics. `code` and `field_type` are intentionally absent
    — they are immutable (see CustomFieldCreate)."""

    name: str | None = Field(default=None, min_length=1, max_length=100)
    options: list[CustomFieldOption] | None = None
    auto_fill: bool | None = None
    is_filterable: bool | None = None
    is_readonly: bool | None = None
    is_mandatory: bool | None = None
    sort_order: int | None = None

    @model_validator(mode="after")
    def _options_unique(self) -> "CustomFieldUpdate":
        if self.options is not None:
            seen = {o.code for o in self.options}
            if len(seen) != len(self.options):
                raise ValueError("option codes must be unique")
        return self


class CustomFieldOut(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str
    code: str
    field_type: str
    options: list[CustomFieldOption] = []
    auto_fill: bool
    is_filterable: bool
    is_readonly: bool
    is_mandatory: bool
    sort_order: int
    created_at: datetime
    updated_at: datetime


class LeadCustomFieldValue(BaseModel):
    """One field's current value on a lead, echoed back in LeadOut and
    the lead's custom-fields endpoint. `value` is whatever the field
    type stores: a string, number, ISO date string, option code, or
    list of option codes. Null = not set."""

    model_config = ConfigDict(extra="ignore")

    code: str
    value: Any | None = None
