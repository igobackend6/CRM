from enum import Enum
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class BulkLeadAction(str, Enum):
    """Phase 13 §"Bulk Actions". Matches the spec's four supported
    actions; `change_status` reuses the same word-shape as
    `LeadStatusChange` (pipeline.py) rather than a hyphen/space variant."""

    ASSIGN = "assign"
    UNASSIGN = "unassign"
    CHANGE_STATUS = "change_status"
    DELETE = "delete"


class BulkLeadActionRequest(BaseModel):
    """`member_id`/`status_id` are only required for their matching
    action (checked in LeadService.bulk_update_leads, not here — same
    "business-rule, not schema-shape" split already used for e.g.
    LeadService._default_status_id). Bounded to 200 leads per request so
    one call can't be used to silently hang the request/DB with an
    unbounded batch."""

    lead_ids: list[UUID] = Field(min_length=1, max_length=200)
    action: BulkLeadAction
    member_id: UUID | None = None
    status_id: UUID | None = None


class BulkLeadActionResult(BaseModel):
    model_config = ConfigDict(extra="ignore")

    lead_id: UUID
    success: bool
    error: str | None = None


class BulkLeadActionResponse(BaseModel):
    action: BulkLeadAction
    total: int
    succeeded: int
    failed: int
    results: list[BulkLeadActionResult]


class LeadImportRequest(BaseModel):
    """Raw CSV text in a JSON body rather than `multipart/form-data`:
    `python-multipart` isn't an existing backend dependency (Phase 13
    §"If the existing API/file handling architecture makes multipart CSV
    unnecessarily complex, implement the smallest safe approach
    consistent with the project") and every other endpoint in this API
    already takes a plain JSON body — this keeps the same shape rather
    than introducing a second request-encoding convention plus a new
    dependency for one endpoint. 2MB is a generous bound for a CSV of
    lead rows while still rejecting a pathological upload outright."""

    csv_content: str = Field(min_length=1, max_length=2_000_000)


class LeadImportRowError(BaseModel):
    row: int
    error: str


class LeadImportResponse(BaseModel):
    total: int
    created: int
    failed: int
    errors: list[LeadImportRowError]
