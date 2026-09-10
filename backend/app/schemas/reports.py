from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.schemas.calls import CallOutcomeOut
from app.schemas.leads import LeadSourceOut, LeadStatusOut, MemberSummary

# Phase 21C — Complete Reports & Analytics. Reuses existing shapes
# (LeadStatusOut, LeadSourceOut, MemberSummary) unchanged rather than
# duplicating them (same rule Phase 17's LeadsByStatusItem already
# followed) — see backend/app/schemas/dashboard.py's own note.


class CallOutcomeBreakdownItem(BaseModel):
    model_config = ConfigDict(extra="ignore")

    outcome: CallOutcomeOut
    count: int


class CallMetrics(BaseModel):
    total_calls: int
    connected_calls: int
    unconnected_calls: int
    completed_calls: int
    calls_by_outcome: list[CallOutcomeBreakdownItem]
    total_talk_time_seconds: int
    average_call_duration_seconds: float


class FollowUpMetrics(BaseModel):
    total_follow_ups: int
    pending_follow_ups: int
    completed_follow_ups: int
    cancelled_follow_ups: int
    overdue_follow_ups: int


class LeadMetrics(BaseModel):
    leads_created: int
    leads_assigned: int
    leads_contacted: int
    leads_converted: int
    conversion_rate: float


class ReportStatusItem(BaseModel):
    model_config = ConfigDict(extra="ignore")

    status: LeadStatusOut
    count: int


class PipelineSnapshot(BaseModel):
    """The scoped ("mine", for the personal report) pipeline slice — see
    `PipelineReportOut` below for the workspace-wide equivalent."""

    model_config = ConfigDict(extra="ignore")

    leads_by_status: list[ReportStatusItem]
    customer_count: int
    lost_leads: int
    active_pipeline_count: int


class ReportRangeOut(BaseModel):
    """Echoes the resolved date window back to the caller (Phase 21C
    §"Date Range Support") so a client can display "showing data for
    X-Y" without re-deriving the range calculation itself. `since`/
    `until` are null only for `range="all_time"`."""

    range: str
    since: datetime | None = None
    until: datetime | None = None


class PersonalReportOut(ReportRangeOut):
    calls: CallMetrics
    follow_ups: FollowUpMetrics
    leads: LeadMetrics
    pipeline: PipelineSnapshot


class TeamMemberReportRow(BaseModel):
    model_config = ConfigDict(extra="ignore")

    member: MemberSummary
    leads_assigned: int
    leads_converted: int
    conversion_rate: float
    calls: int
    connected_calls: int
    talk_time_seconds: int
    completed_follow_ups: int
    pending_follow_ups: int


class TeamTotals(BaseModel):
    leads_assigned: int
    leads_converted: int
    conversion_rate: float
    calls: int
    connected_calls: int
    talk_time_seconds: int
    completed_follow_ups: int
    pending_follow_ups: int


class TeamReportOut(ReportRangeOut):
    items: list[TeamMemberReportRow]
    total: int
    limit: int
    offset: int
    totals: TeamTotals


class PipelineSourceItem(BaseModel):
    model_config = ConfigDict(extra="ignore")

    source: LeadSourceOut
    leads_count: int
    converted_count: int
    conversion_rate: float


class PipelinePriorityItem(BaseModel):
    priority: str
    count: int
    percentage: float


class PipelineStatusItem(BaseModel):
    model_config = ConfigDict(extra="ignore")

    status: LeadStatusOut
    count: int
    percentage: float


class PipelineReportOut(ReportRangeOut):
    leads_by_status: list[PipelineStatusItem]
    converted_customers: int
    lost_leads: int
    active_leads: int
    source_performance: list[PipelineSourceItem]
    priority_distribution: list[PipelinePriorityItem]
