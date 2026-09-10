from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.schemas.leads import LeadStatusOut, MemberSummary


class PipelineLeadCard(BaseModel):
    """The minimum a pipeline column needs to render one lead (Phase 12
    §"Backend": "Each lead card should contain only ..."). Deliberately
    narrower than `LeadOut` — no tags/source/created_by/is_customer —
    since the pipeline board renders many of these at once."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    name: str
    phone: str | None = None
    email: str | None = None
    priority: str
    status: LeadStatusOut | None = None
    assigned_member: MemberSummary | None = None
    updated_at: datetime


class PipelineColumn(BaseModel):
    """One `lead_statuses` column and the (bounded, paginated) leads
    currently in it. `total` is the full count for this status under the
    current filters, independent of how many `leads` this page carries —
    lets the client show "N of total" without a second request."""

    model_config = ConfigDict(extra="ignore")

    status: LeadStatusOut
    leads: list[PipelineLeadCard]
    total: int


class PipelineResponse(BaseModel):
    columns: list[PipelineColumn]
    limit: int
    offset: int


class LeadStatusChange(BaseModel):
    status_id: UUID
