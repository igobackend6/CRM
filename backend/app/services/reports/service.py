from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.date_ranges import resolve_report_range, utc_now
from app.core.exceptions import ValidationError
from app.core.timeparse import parse_supabase_datetime
from app.repositories.calls import CallRepository
from app.repositories.followups import FollowUpRepository
from app.repositories.lead_reference import CallOutcomeRepository, LeadSourceRepository, LeadStatusRepository, MemberRepository
from app.repositories.leads import LeadRepository

# Phase 21C — Complete Reports & Analytics. Orchestrates the *existing*
# Phase 5-19 repositories (extended with a handful of new, narrowly-
# scoped filter params — see each repository's own Phase 21C docstring
# notes) into three read-only reports. No new tables besides one DB-side
# SUM/AVG function (supabase/migrations/000024_report_aggregate_functions.sql)
# — every count below is the same bounded `count="exact"` pattern
# DashboardService already established, just with a report-appropriate
# date window and (for team/pipeline) a wider scope than "the current
# member". Authorization is never decided here — routes
# (api/v1/reports.py) already enforce workspace membership (personal) or
# `Permission.REPORTS_READ` (team/pipeline) before any method here runs,
# and RLS still applies underneath regardless.


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


class ReportService:
    def __init__(self, client: Client):
        self._client = client
        self._leads = LeadRepository(client)
        self._statuses = LeadStatusRepository(client)
        self._sources = LeadSourceRepository(client)
        self._follow_ups = FollowUpRepository(client)
        self._calls = CallRepository(client)
        self._call_outcomes = CallOutcomeRepository(client)
        self._members = MemberRepository(client)

    # ---- shared range resolution ----

    def _resolve_range(
        self, range_key: str, custom_since: datetime | None, custom_until: datetime | None
    ) -> tuple[datetime | None, datetime | None]:
        return resolve_report_range(range_key, now=utc_now(), custom_since=custom_since, custom_until=custom_until)

    @staticmethod
    def _range_out(range_key: str, since: datetime | None, until: datetime | None) -> dict[str, Any]:
        return {"range": range_key, "since": since, "until": until}

    # ---- Personal report (§"Personal Reports") ----

    def get_personal_report(
        self,
        workspace_id: UUID,
        *,
        range_key: str,
        custom_since: datetime | None = None,
        custom_until: datetime | None = None,
    ) -> dict[str, Any]:
        since, until = self._resolve_range(range_key, custom_since, custom_until)
        since_iso, until_iso = _iso(since), _iso(until)
        member_id = self._current_member_id(workspace_id)
        now_iso = _iso(utc_now())

        result = self._range_out(range_key, since, until)
        result["calls"] = self._call_metrics(workspace_id, agent_member_id=member_id, since=since_iso, until=until_iso)
        result["follow_ups"] = self._follow_up_metrics(
            workspace_id, assigned_member_id=member_id, since=since_iso, until=until_iso, now_iso=now_iso
        )
        result["leads"] = self._personal_lead_metrics(workspace_id, member_id, since, until, since_iso, until_iso)
        result["pipeline"] = self._pipeline_snapshot(workspace_id, member_id, since, until)
        return result

    def _call_metrics(
        self, workspace_id: UUID, *, agent_member_id: UUID | str | None, since: str | None, until: str | None
    ) -> dict[str, Any]:
        total_calls = self._calls.count_filtered(workspace_id, agent_member_id=agent_member_id, since=since, until=until)
        connected_calls = self._calls.count_filtered(
            workspace_id, agent_member_id=agent_member_id, since=since, until=until, states=["CONNECTED", "ENDED"]
        )
        completed_calls = self._calls.count_filtered(
            workspace_id, agent_member_id=agent_member_id, since=since, until=until, states=["ENDED"]
        )
        unconnected_calls = self._calls.count_filtered(
            workspace_id,
            agent_member_id=agent_member_id,
            since=since,
            until=until,
            states=["FAILED", "MISSED", "CANCELLED"],
        )
        outcomes = self._call_outcomes.list_for_workspace(workspace_id)
        calls_by_outcome = [
            {
                "outcome": outcome,
                "count": self._calls.count_filtered(
                    workspace_id,
                    agent_member_id=agent_member_id,
                    since=since,
                    until=until,
                    outcome_id=outcome["id"],
                ),
            }
            for outcome in outcomes
        ]
        total_talk_time_seconds, average_call_duration_seconds = self._calls.duration_stats(
            workspace_id, agent_member_id=agent_member_id, since=since, until=until
        )
        return {
            "total_calls": total_calls,
            "connected_calls": connected_calls,
            "unconnected_calls": unconnected_calls,
            "completed_calls": completed_calls,
            "calls_by_outcome": calls_by_outcome,
            "total_talk_time_seconds": total_talk_time_seconds,
            "average_call_duration_seconds": average_call_duration_seconds,
        }

    def _follow_up_metrics(
        self,
        workspace_id: UUID,
        *,
        assigned_member_id: UUID | str | None,
        since: str | None,
        until: str | None,
        now_iso: str,
    ) -> dict[str, Any]:
        return {
            "total_follow_ups": self._follow_ups.count_filtered(
                workspace_id, assigned_member_id=assigned_member_id, since=since, until=until
            ),
            "pending_follow_ups": self._follow_ups.count_filtered(
                workspace_id, status="pending", assigned_member_id=assigned_member_id, since=since, until=until
            ),
            "completed_follow_ups": self._follow_ups.count_completed(
                workspace_id, assigned_member_id=assigned_member_id, since=since, until=until
            ),
            "cancelled_follow_ups": self._follow_ups.count_filtered(
                workspace_id, status="cancelled", assigned_member_id=assigned_member_id, since=since, until=until
            ),
            "overdue_follow_ups": self._follow_ups.count_overdue(
                workspace_id, now_iso, assigned_member_id=assigned_member_id
            ),
        }

    def _personal_lead_metrics(
        self,
        workspace_id: UUID,
        member_id: str,
        since: datetime | None,
        until: datetime | None,
        since_iso: str | None,
        until_iso: str | None,
    ) -> dict[str, Any]:
        _, leads_created = self._leads.list_for_workspace(
            workspace_id, created_by_member_id=member_id, created_from=since, created_to=until, limit=1
        )
        _, leads_assigned = self._leads.list_for_workspace(
            workspace_id, assigned_member_id=member_id, created_from=since, created_to=until, limit=1
        )
        leads_contacted = len(
            self._calls.list_contacted_lead_ids(workspace_id, agent_member_id=member_id, since=since_iso, until=until_iso)
        )
        leads_converted = self._leads.count_converted(
            workspace_id, since=since_iso, until=until_iso, assigned_member_id=member_id
        )
        conversion_rate = (leads_converted / leads_assigned) if leads_assigned > 0 else 0.0
        return {
            "leads_created": leads_created,
            "leads_assigned": leads_assigned,
            "leads_contacted": leads_contacted,
            "leads_converted": leads_converted,
            "conversion_rate": conversion_rate,
        }

    def _pipeline_snapshot(
        self, workspace_id: UUID, member_id: str, since: datetime | None, until: datetime | None
    ) -> dict[str, Any]:
        """Member-scoped "my pipeline" slice — all-time (not range-
        windowed) for `customer_count`/`lost_leads`/`active_pipeline_count`,
        matching DashboardService.get_summary's own "customers" KPI
        precedent: these describe where a lead sits *right now*, not how
        many entered a status during the selected window (that's what
        `leads_by_status` below, deliberately still range-windowed to
        match Phase 17's own `_leads_by_status` interpretation, is for)."""
        statuses = self._statuses.list_for_workspace(workspace_id)
        leads_by_status = []
        for status in statuses:
            _, count = self._leads.list_for_workspace(
                workspace_id, status_id=status["id"], assigned_member_id=member_id, created_from=since, created_to=until, limit=1
            )
            leads_by_status.append({"status": status, "count": count})

        _, customer_count = self._leads.list_for_workspace(
            workspace_id, assigned_member_id=member_id, is_customer=True, limit=1
        )
        _, total_non_customer = self._leads.list_for_workspace(
            workspace_id, assigned_member_id=member_id, is_customer=False, limit=1
        )
        lost_status_ids = [s["id"] for s in statuses if s.get("stage") == "closed_lost"]
        lost_leads = 0
        for status_id in lost_status_ids:
            _, count = self._leads.list_for_workspace(
                workspace_id, status_id=status_id, assigned_member_id=member_id, limit=1
            )
            lost_leads += count
        active_pipeline_count = max(total_non_customer - lost_leads, 0)

        return {
            "leads_by_status": leads_by_status,
            "customer_count": customer_count,
            "lost_leads": lost_leads,
            "active_pipeline_count": active_pipeline_count,
        }

    # ---- Call trends (Analytics hub → Call Analytics) ----

    _CALL_TREND_STEPS = {"hour": timedelta(hours=1), "day": timedelta(days=1)}
    # Bounds the zero-filled bucket list (and so the response) no matter
    # what window a client asks for: 31 days of hours is 744, a year of
    # days is 366 — anything past this is a misuse, not a real picker.
    _CALL_TREND_MAX_BUCKETS = 800

    def get_call_trends(
        self,
        workspace_id: UUID,
        *,
        since: datetime,
        until: datetime,
        granularity: str,
        direction: str,
    ) -> dict[str, Any]:
        """The current member's own calls in `[since, until)`, bucketed
        into zero-filled `hour`/`day` steps counted from `since` itself.

        Buckets are anchored to `since` rather than to a UTC calendar
        boundary on purpose: the client sends the instant of its own
        *local* midnight (Day/Week/Month picker), so counting steps from
        there makes "hourly" mean the user's local hours without the
        server knowing or storing any timezone (there is none anywhere
        in this schema — see core/date_ranges.py). Across a DST change a
        local day is 23/25 hours and the last bucket edge shifts by an
        hour; acceptable for a trends chart and documented here rather
        than papered over.

        Scoped to the current member (same as the personal report) —
        team-wide call numbers are the Team report's job. `direction`
        is `all`, `inbound` or `outbound`."""
        # A client that sends a bare timestamp (no offset) means UTC —
        # mixing naive and aware datetimes below would otherwise raise.
        if since.tzinfo is None:
            since = since.replace(tzinfo=timezone.utc)
        if until.tzinfo is None:
            until = until.replace(tzinfo=timezone.utc)
        if granularity not in self._CALL_TREND_STEPS:
            raise ValidationError("granularity must be 'hour' or 'day'.")
        if direction not in ("all", "inbound", "outbound"):
            raise ValidationError("direction must be 'all', 'inbound' or 'outbound'.")
        if since >= until:
            raise ValidationError("'since' must be before 'until'.")

        step = self._CALL_TREND_STEPS[granularity]
        bucket_count = -(-(until - since) // step)  # ceil division on timedeltas
        if bucket_count > self._CALL_TREND_MAX_BUCKETS:
            raise ValidationError("That window is too long for the chosen granularity.")

        member_id = self._current_member_id(workspace_id)
        rows = self._calls.list_for_trends(
            workspace_id,
            agent_member_id=member_id,
            since=since.isoformat(),
            until=until.isoformat(),
            direction=None if direction == "all" else direction,
        )

        calls = [0] * bucket_count
        talk = [0] * bucket_count
        leads: list[set[str]] = [set() for _ in range(bucket_count)]
        window_leads: set[str] = set()
        for row in rows:
            index = (parse_supabase_datetime(row["started_at"]) - since) // step
            if not 0 <= index < bucket_count:
                continue
            calls[index] += 1
            talk[index] += int(row.get("duration_seconds") or 0)
            lead_id = row.get("lead_id")
            if lead_id:
                leads[index].add(lead_id)
                window_leads.add(lead_id)

        return {
            "since": since,
            "until": until,
            "granularity": granularity,
            "direction": direction,
            "buckets": [
                {
                    "start": since + step * i,
                    "calls": calls[i],
                    "unique_leads": len(leads[i]),
                    "talk_time_seconds": talk[i],
                }
                for i in range(bucket_count)
            ],
            "total_calls": sum(calls),
            "unique_leads": len(window_leads),
            "total_talk_time_seconds": sum(talk),
        }

    # ---- Team report (§"Team Reports") ----

    def get_team_report(
        self,
        workspace_id: UUID,
        *,
        range_key: str,
        custom_since: datetime | None = None,
        custom_until: datetime | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> dict[str, Any]:
        since, until = self._resolve_range(range_key, custom_since, custom_until)
        since_iso, until_iso = _iso(since), _iso(until)

        members = self._members.list_active(workspace_id)
        rows: list[dict[str, Any]] = []
        for member in members:
            member_id = member["id"]
            _, leads_assigned = self._leads.list_for_workspace(
                workspace_id, assigned_member_id=member_id, created_from=since, created_to=until, limit=1
            )
            leads_converted = self._leads.count_converted(
                workspace_id, since=since_iso, until=until_iso, assigned_member_id=member_id
            )
            calls_total = self._calls.count_filtered(workspace_id, agent_member_id=member_id, since=since_iso, until=until_iso)
            connected_calls = self._calls.count_filtered(
                workspace_id, agent_member_id=member_id, since=since_iso, until=until_iso, states=["CONNECTED", "ENDED"]
            )
            talk_time_seconds, _ = self._calls.duration_stats(
                workspace_id, agent_member_id=member_id, since=since_iso, until=until_iso
            )
            completed_follow_ups = self._follow_ups.count_completed(
                workspace_id, assigned_member_id=member_id, since=since_iso, until=until_iso
            )
            pending_follow_ups = self._follow_ups.count_filtered(
                workspace_id, status="pending", assigned_member_id=member_id, since=since_iso, until=until_iso
            )
            rows.append(
                {
                    "member": {"id": member_id, "full_name": member.get("full_name")},
                    "leads_assigned": leads_assigned,
                    "leads_converted": leads_converted,
                    "conversion_rate": (leads_converted / leads_assigned) if leads_assigned > 0 else 0.0,
                    "calls": calls_total,
                    "connected_calls": connected_calls,
                    "talk_time_seconds": talk_time_seconds,
                    "completed_follow_ups": completed_follow_ups,
                    "pending_follow_ups": pending_follow_ups,
                }
            )

        # Deterministic ranking (also doubles as Flutter's optional
        # "sortable ranking" — §"Team Reports"): most conversions first,
        # member name as a stable tie-break so page order never flaps
        # between identical requests.
        rows.sort(key=lambda r: (-r["leads_converted"], (r["member"]["full_name"] or "")))

        total_assigned = sum(r["leads_assigned"] for r in rows)
        total_converted = sum(r["leads_converted"] for r in rows)
        totals = {
            "leads_assigned": total_assigned,
            "leads_converted": total_converted,
            "conversion_rate": (total_converted / total_assigned) if total_assigned > 0 else 0.0,
            "calls": sum(r["calls"] for r in rows),
            "connected_calls": sum(r["connected_calls"] for r in rows),
            "talk_time_seconds": sum(r["talk_time_seconds"] for r in rows),
            "completed_follow_ups": sum(r["completed_follow_ups"] for r in rows),
            "pending_follow_ups": sum(r["pending_follow_ups"] for r in rows),
        }

        result = self._range_out(range_key, since, until)
        result.update(
            {
                "items": rows[offset : offset + limit],
                "total": len(rows),
                "limit": limit,
                "offset": offset,
                "totals": totals,
            }
        )
        return result

    # ---- Pipeline report (§"Pipeline Reports") ----

    def get_pipeline_report(
        self,
        workspace_id: UUID,
        *,
        range_key: str,
        custom_since: datetime | None = None,
        custom_until: datetime | None = None,
    ) -> dict[str, Any]:
        since, until = self._resolve_range(range_key, custom_since, custom_until)
        since_iso, until_iso = _iso(since), _iso(until)

        statuses = self._statuses.list_for_workspace(workspace_id)
        status_counts: list[tuple[dict[str, Any], int]] = []
        for status in statuses:
            _, count = self._leads.list_for_workspace(
                workspace_id, status_id=status["id"], created_from=since, created_to=until, limit=1
            )
            status_counts.append((status, count))
        status_total = sum(c for _, c in status_counts) or 0
        leads_by_status = [
            {"status": status, "count": count, "percentage": _percentage(count, status_total)}
            for status, count in status_counts
        ]

        converted_customers = self._leads.count_converted(workspace_id, since=since_iso, until=until_iso)
        lost_status_ids = [s["id"] for s in statuses if s.get("stage") == "closed_lost"]
        lost_leads = 0
        for status_id in lost_status_ids:
            _, count = self._leads.list_for_workspace(workspace_id, status_id=status_id, limit=1)
            lost_leads += count
        _, total_non_customer = self._leads.list_for_workspace(workspace_id, is_customer=False, limit=1)
        active_leads = max(total_non_customer - lost_leads, 0)

        sources = self._sources.list_for_workspace(workspace_id)
        source_performance = []
        for source in sources:
            _, leads_count = self._leads.list_for_workspace(
                workspace_id, source_id=source["id"], created_from=since, created_to=until, limit=1
            )
            converted_count = self._leads.count_converted(
                workspace_id, since=since_iso, until=until_iso, source_id=source["id"]
            )
            source_performance.append(
                {
                    "source": source,
                    "leads_count": leads_count,
                    "converted_count": converted_count,
                    "conversion_rate": (converted_count / leads_count) if leads_count > 0 else 0.0,
                }
            )

        priority_counts: list[tuple[str, int]] = []
        for priority in ("low", "medium", "high", "urgent"):
            _, count = self._leads.list_for_workspace(
                workspace_id, priority=priority, created_from=since, created_to=until, limit=1
            )
            priority_counts.append((priority, count))
        priority_total = sum(c for _, c in priority_counts) or 0
        priority_distribution = [
            {"priority": priority, "count": count, "percentage": _percentage(count, priority_total)}
            for priority, count in priority_counts
        ]

        result = self._range_out(range_key, since, until)
        result.update(
            {
                "leads_by_status": leads_by_status,
                "converted_customers": converted_customers,
                "lost_leads": lost_leads,
                "active_leads": active_leads,
                "source_performance": source_performance,
                "priority_distribution": priority_distribution,
            }
        )
        return result

    # ---- helpers ----

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id


def _percentage(count: int, total: int) -> float:
    """Deterministic rounding (Phase 21C §"Pipeline Reports": "use
    deterministic rounding, document the calculation") — one decimal
    place, zero-guarded. `round()` on a float here is fine (not
    financial data, and every caller only ever displays it), unlike
    money math elsewhere in this codebase which would need Decimal."""
    if total <= 0:
        return 0.0
    return round((count / total) * 100, 1)
