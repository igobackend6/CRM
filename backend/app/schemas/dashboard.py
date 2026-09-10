from pydantic import BaseModel, ConfigDict

from app.schemas.leads import LeadStatusOut, MemberSummary

# The recent-activity feed reuses Phase 8's TimelineItemOut/TimelineResponse
# shapes unchanged (see app/api/v1/dashboard.py) — same id-prefix-by-source,
# actor_member, summary/details contract as Customer 360's timeline, just
# assembled workspace-wide instead of per-lead. No separate
# "DashboardActivityItemOut" schema — Phase 11 §"reuse instead of
# duplicating logic".


class LeadsByStatusItem(BaseModel):
    """One `lead_statuses` column's lead count — the pipeline
    distribution KPI (Phase 17 §"Pipeline metrics"). Reuses the existing
    `LeadStatusOut` shape unchanged (same status object the Phase 12
    pipeline board already returns) rather than a slimmer duplicate."""

    model_config = ConfigDict(extra="ignore")

    status: LeadStatusOut
    count: int


class TeamProductivityRow(BaseModel):
    """One member's productivity row (Phase 17 §"Team productivity").
    Only members with at least one nonzero count are included — see
    DashboardService._team_productivity's own docstring for why (RLS
    already means a team_mate's own request only ever sees nonzero
    counts for themselves; omitting all-zero rows turns that into "the
    table naturally shows only what you're allowed to see" instead of a
    wall of zeros for every colleague)."""

    model_config = ConfigDict(extra="ignore")

    member: MemberSummary
    leads_count: int
    calls_count: int
    completed_follow_ups_count: int


class DashboardSummaryOut(BaseModel):
    """`GET /workspaces/{workspace_id}/dashboard/summary` (Phase 11; extended
    Phase 17). Every count field is a single aggregate — RLS (via the
    caller's own request-scoped client) already scopes what's counted to
    what that member can see (e.g. a team_mate's `total_active_leads`
    naturally only counts their own leads, a manager's counts the whole
    workspace — leads_select/follow_ups_select/calls_select's own
    manager-or-self rules, 000014_rls_policies.sql), so this schema
    carries no separate "my" vs "workspace" variants.

    Phase 17 field split — two families, matching the split in
    DashboardService.get_summary's own docstring:

    * The original 9 Phase 11 fields (`total_active_leads` through
      `unread_notifications`) are point-in-time *state* counts ("how big
      is each queue right now") and are ALWAYS computed exactly as
      before, regardless of `range` — Phase 17 §"Default should preserve
      current dashboard behavior" extended to mean these fields never
      change meaning, not just that the default parameter does nothing.
    * Every field below `range` is a Phase 17 *period* metric —
      computed over the `[since, until)` window `range` selects
      (all-time when `range="all"`, the default).
    """

    # ---- Phase 11 — unchanged ----
    total_active_leads: int
    new_leads: int
    customers: int
    pending_follow_ups: int
    overdue_follow_ups: int
    completed_follow_ups: int
    total_calls: int
    todays_calls: int
    unread_notifications: int

    # ---- Phase 17 — period analytics ----
    range: str
    leads_created_in_range: int
    converted_leads_in_range: int
    conversion_rate: float
    calls_connected_in_range: int
    calls_completed_in_range: int
    completed_follow_ups_in_range: int
    leads_by_status: list[LeadsByStatusItem]
    team_productivity: list[TeamProductivityRow]
