from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from supabase import Client

from app.core.exceptions import ValidationError
from app.core.timeparse import parse_supabase_datetime
from app.repositories.allocations import AllocationRepository
from app.repositories.calls import CallRepository
from app.repositories.followups import FollowUpRepository
from app.repositories.lead_reference import InteractionRepository, LeadStatusRepository, MemberRepository
from app.repositories.leads import LeadRepository
from app.repositories.notifications import NotificationRepository
from app.services.customer360.service import CustomerService

# Phase 17 §"Date Range" — the four ranges the dashboard's filter chip
# accepts. Every boundary is computed in UTC, matching every other
# timestamp computation already in this file (`today_start` below
# predates Phase 17) and every `timestamptz` column in the schema — this
# codebase has never had a per-user timezone preference, so "this week"/
# "this month" mean the calendar week/month in UTC, not the viewer's
# local calendar day. Documented as a known limitation (Phase 17 report
# §"Known limitations"), not silently assumed.
_DATE_RANGES = {"all", "today", "this_week", "this_month"}


def _iso(value: datetime) -> str:
    return value.isoformat()


def _range_bounds(range_key: str, now: datetime) -> tuple[datetime | None, datetime | None]:
    """`[since, until)` for one of `_DATE_RANGES` — `datetime`s (not ISO
    strings) so a call site can hand `since` straight to
    `LeadRepository.list_for_workspace`'s `created_from: datetime`
    param, and stringify it (`_iso`) only for the repo methods that
    already take a plain `str`. `until=None` always means "open-ended,
    up to now" (never a future upper bound), matching `count_since`'s
    existing Phase 11 convention (`todays_calls`) rather than
    introducing a second "as of now" idiom. `since=None` (only for
    `"all"`) means no lower bound at all — the exact query every Phase
    11 field already ran, which is how `range="all"` reproduces the
    original, pre-Phase-17 values precisely."""
    if range_key == "today":
        since = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif range_key == "this_week":
        # Monday-start ISO week.
        since = (now - timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    elif range_key == "this_month":
        since = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    else:
        return None, None
    return since, None


def _iso_or_none(value: datetime | None) -> str | None:
    return _iso(value) if value is not None else None


class DashboardService:
    """Phase 11 — Dashboard & CRM Analytics; extended Phase 17 —
    Productivity & Sales Analytics. Orchestrates the *existing*
    Phase 5-10 repositories into three read-only views (a KPI summary, a
    workspace-wide recent-activity feed, and — as of Phase 17 — the same
    summary's own period/productivity fields) — no new tables, no
    duplicated query logic: every count here either reuses an existing
    `list_for_workspace`-style method's own `total` (the "run the same
    query the list screen already runs, but with limit=1 and keep only
    the count" trick), a small single-purpose count method added
    alongside it in Phase 11, or a small date-window-aware count method
    added alongside it in Phase 17 (see each repository's own docstring
    note). Same division of responsibility as every other service in
    this codebase: authorization is never decided here — a route (via
    api/dependencies.py) has already enforced workspace membership
    before any method here runs, and RLS still applies underneath
    regardless, which is *why* every count below is naturally
    role-scoped for free (a team_mate's counts cover only their own
    leads/calls/follow-ups, a manager's cover the whole workspace — see
    leads_select/follow_ups_select/calls_select in
    000014_rls_policies.sql) without this class branching on role at
    all — including the Phase 17 team-productivity breakdown, see
    `_team_productivity`'s own docstring.
    """

    def __init__(self, client: Client):
        self._client = client
        self._leads = LeadRepository(client)
        self._statuses = LeadStatusRepository(client)
        self._follow_ups = FollowUpRepository(client)
        self._calls = CallRepository(client)
        self._notifications = NotificationRepository(client)
        self._interactions = InteractionRepository(client)
        self._allocations = AllocationRepository(client)
        self._members = MemberRepository(client)

    # ---- summary (§"Backend") ----

    def get_summary(self, workspace_id: UUID, *, range_key: str = "all") -> dict[str, Any]:
        if range_key not in _DATE_RANGES:
            # Defensive — the route already validates this via a Query
            # pattern constraint; a service-level caller (or a future
            # route) gets the same guarantee rather than an obscure
            # downstream error.
            raise ValidationError(f"range must be one of {sorted(_DATE_RANGES)}.")

        recipient_member_id = self._current_member_id(workspace_id)
        now = datetime.now(timezone.utc)
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

        _, total_active_leads = self._leads.list_for_workspace(workspace_id, limit=1)
        _, customers = self._leads.list_for_workspace(workspace_id, is_customer=True, limit=1)
        _, pending_follow_ups = self._follow_ups.list_for_workspace(workspace_id, status="pending", limit=1)
        _, completed_follow_ups = self._follow_ups.list_for_workspace(workspace_id, status="completed", limit=1)
        _, total_calls = self._calls.list_for_workspace(workspace_id, limit=1)
        _, unread_notifications = self._notifications.list_for_workspace(
            workspace_id, recipient_member_id, is_read=False, limit=1
        )

        default_status_id = self._default_status_id(workspace_id)
        if default_status_id is not None:
            _, new_leads = self._leads.list_for_workspace(workspace_id, status_id=default_status_id, limit=1)
        else:
            # No default lead status configured for this workspace (an
            # admin never set one) — "new leads" has nothing to count
            # against rather than guessing a fallback definition.
            new_leads = 0

        summary: dict[str, Any] = {
            "total_active_leads": total_active_leads,
            "new_leads": new_leads,
            "customers": customers,
            "pending_follow_ups": pending_follow_ups,
            "overdue_follow_ups": self._follow_ups.count_overdue(workspace_id, _iso(now)),
            "completed_follow_ups": completed_follow_ups,
            "total_calls": total_calls,
            "todays_calls": self._calls.count_since(workspace_id, _iso(today_start)),
            "unread_notifications": unread_notifications,
        }
        summary.update(self._period_analytics(workspace_id, range_key, now))
        return summary

    # ---- Phase 17 — period analytics ----

    def _period_analytics(self, workspace_id: UUID, range_key: str, now: datetime) -> dict[str, Any]:
        since, until = _range_bounds(range_key, now)
        since_iso, until_iso = _iso_or_none(since), _iso_or_none(until)

        _, leads_created = self._leads.list_for_workspace(workspace_id, created_from=since, limit=1)
        converted = self._leads.count_converted(workspace_id, since=since_iso, until=until_iso)
        conversion_rate = (converted / leads_created) if leads_created > 0 else 0.0

        calls_connected = self._calls.count_filtered(
            workspace_id, since=since_iso, until=until_iso, states=["CONNECTED", "ENDED"]
        )
        calls_completed = self._calls.count_filtered(workspace_id, since=since_iso, until=until_iso, states=["ENDED"])

        completed_follow_ups_in_range = self._follow_ups.count_completed(workspace_id, since=since_iso, until=until_iso)

        return {
            "range": range_key,
            "leads_created_in_range": leads_created,
            "converted_leads_in_range": converted,
            "conversion_rate": conversion_rate,
            "calls_connected_in_range": calls_connected,
            "calls_completed_in_range": calls_completed,
            "completed_follow_ups_in_range": completed_follow_ups_in_range,
            "leads_by_status": self._leads_by_status(workspace_id, since),
            "team_productivity": self._team_productivity(workspace_id, since, since_iso, until_iso),
        }

    def _leads_by_status(self, workspace_id: UUID, since: datetime | None) -> list[dict[str, Any]]:
        """Pipeline distribution (Phase 17 §"Pipeline metrics") — one
        bounded count query per workspace status, exactly
        `LeadService.list_pipeline`'s own established shape ("there are
        only ever a handful of statuses per workspace" — that method's
        docstring), just a count instead of a page of lead cards. When
        `since` is set, this reads as "of the leads *created* in this
        window, how many are currently in each stage" — a deliberate,
        documented interpretation (§"Known limitations": it is not a
        historical snapshot of where those leads stood at the time,
        Postgres has no such history to query)."""
        statuses = self._statuses.list_for_workspace(workspace_id)
        result = []
        for status in statuses:
            _, count = self._leads.list_for_workspace(workspace_id, status_id=status["id"], created_from=since, limit=1)
            result.append({"status": status, "count": count})
        return result

    def _team_productivity(
        self, workspace_id: UUID, since: datetime | None, since_iso: str | None, until_iso: str | None
    ) -> list[dict[str, Any]]:
        """Per-member productivity (Phase 17 §"Team productivity") — one
        bounded set of count queries per *active member* (typically a
        handful to a few dozen per workspace, never scaling with
        lead/call/follow-up volume — the same "small, known cardinality"
        reasoning `_leads_by_status`/`list_pipeline` already rely on for
        looping per-status instead of per-row).

        No manager-only gate here: `leads.list_for_workspace`/
        `calls.count_filtered`/`follow_ups.count_completed` all run
        through this request's own RLS-scoped client, and
        leads_select/calls_select/follow_ups_select
        (000014_rls_policies.sql) already restrict a team_mate's own
        query to rows they're assigned/created — so a team_mate's counts
        for every OTHER member come back zero automatically, never a
        leaked real number. Filtering those all-zero rows out below
        turns that into "a team_mate's table only ever shows their own
        row", which is the correct, minimal-surprise behavior without
        this method ever branching on role."""
        members = self._members.list_active(workspace_id)
        rows: list[dict[str, Any]] = []
        for member in members:
            member_id = member["id"]
            _, leads_count = self._leads.list_for_workspace(
                workspace_id, assigned_member_id=member_id, created_from=since, limit=1
            )
            calls_count = self._calls.count_filtered(
                workspace_id, agent_member_id=member_id, since=since_iso, until=until_iso
            )
            completed_follow_ups_count = self._follow_ups.count_completed(
                workspace_id, assigned_member_id=member_id, since=since_iso, until=until_iso
            )
            if leads_count == 0 and calls_count == 0 and completed_follow_ups_count == 0:
                continue
            rows.append(
                {
                    "member": {"id": member_id, "full_name": member.get("full_name")},
                    "leads_count": leads_count,
                    "calls_count": calls_count,
                    "completed_follow_ups_count": completed_follow_ups_count,
                }
            )
        return rows

    # ---- recent activity (§"Backend") ----

    def get_recent_activity(self, workspace_id: UUID, *, limit: int, offset: int) -> tuple[list[dict[str, Any]], int]:
        """Same bounded-window merge-and-sort strategy as
        `CustomerService.get_timeline` (Phase 8) — see that method's own
        docstring for why it's correct and why it's a fixed number of
        queries regardless of table size — just workspace-wide instead
        of scoped to one lead, and with `notifications` added as a sixth
        source (Phase 8's timeline predates Phase 10's notifications
        feature, so it never included them).

        Reuses `CustomerService`'s own item-formatting static methods
        (`_call_item`, `_follow_up_item`, `_interaction_item`,
        `_allocation_item`) instead of re-implementing the same
        summary-string logic a second time — Phase 11's own "reuse
        instead of duplicating logic" rule. Only `notifications`, which
        Phase 8 never had, gets a new formatter here.
        """
        recipient_member_id = self._current_member_id(workspace_id)
        window = offset + limit

        calls, calls_total = self._calls.list_for_workspace(workspace_id, limit=window, offset=0)
        follow_ups = self._follow_ups.list_recent_for_workspace(workspace_id, limit=window)
        interactions = self._interactions.list_recent_for_workspace(workspace_id, limit=window)
        allocations = self._allocations.list_recent_for_workspace(workspace_id, limit=window)
        notifications, notifications_total = self._notifications.list_for_workspace(
            workspace_id, recipient_member_id, limit=window, offset=0
        )

        # follow_ups/interactions/allocations don't have their own
        # `list_for_workspace`-with-count method the way calls does
        # (list_recent_for_workspace, added just above, is
        # bounded-window-only, matching its lead-scoped sibling) — reuse
        # the existing `list_for_workspace(limit=1)` trick for follow-ups'
        # total, and the count_for_workspace() added alongside
        # list_recent_for_workspace for interactions/allocations.
        _, follow_ups_total = self._follow_ups.list_for_workspace(workspace_id, limit=1)
        interactions_total = self._interactions.count_for_workspace(workspace_id)
        allocations_total = self._allocations.count_for_workspace(workspace_id)

        total = calls_total + follow_ups_total + interactions_total + allocations_total + notifications_total

        items: list[dict[str, Any]] = []
        items += [CustomerService._call_item(r) for r in calls]
        items += [CustomerService._follow_up_item(r) for r in follow_ups]
        items += [CustomerService._interaction_item(r) for r in interactions]
        items += [CustomerService._allocation_item(r) for r in allocations]
        items += [self._notification_item(r) for r in notifications]

        actor_ids = {i["_actor_id"] for i in items if i.get("_actor_id")}
        member_names = self._members.map_names(workspace_id, list(actor_ids))
        for item in items:
            actor_id = item.pop("_actor_id", None)
            item["actor_member"] = {"id": actor_id, "full_name": member_names.get(actor_id)} if actor_id else None

        items.sort(key=lambda i: i["occurred_at"], reverse=True)
        page = items[offset : offset + limit]
        return page, total

    @staticmethod
    def _notification_item(row: dict[str, Any]) -> dict[str, Any]:
        """The one source `CustomerService.get_timeline` (Phase 8) never
        had — notifications didn't exist until Phase 10 — so this is the
        only item formatter that isn't reused from there. No actor: a
        notification's `recipient_member_id` is always "me" (RLS-scoped),
        and it carries no separate "who caused this" field the way
        calls/follow-ups/allocations do."""
        return {
            "id": f"notification:{row['id']}",
            "type": "notification",
            "occurred_at": _parse(row["created_at"]),
            "_actor_id": None,
            "summary": row.get("title") or "Notification",
            "details": {"body": row.get("body"), "notification_type": row.get("type"), "is_read": row.get("is_read")},
        }

    # ---- helpers ----

    def _current_member_id(self, workspace_id: UUID) -> str:
        result = self._client.rpc("current_member_id", {"p_workspace_id": str(workspace_id)}).execute()
        member_id = result.data
        if not member_id:
            raise ValidationError("Could not resolve your workspace membership.")
        return member_id

    def _default_status_id(self, workspace_id: UUID) -> str | None:
        statuses = self._statuses.list_for_workspace(workspace_id)
        default_status = next((s for s in statuses if s.get("is_default")), None)
        return default_status["id"] if default_status else None


_parse = parse_supabase_datetime
