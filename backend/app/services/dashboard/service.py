from concurrent.futures import ThreadPoolExecutor
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

# The summary is dozens of small, independent count queries, run side by side instead of one after
# another. Supabase closes a connection that carries too many simultaneous requests ("Server
# disconnected"), so the number running at once is capped. Tasks never wait on other pool tasks, so
# the pool cannot deadlock.
_POOL = ThreadPoolExecutor(max_workers=6, thread_name_prefix="dash")


def _run_all(tasks):
    """Runs the zero-argument callables side by side; results come back in the same order, and the
    first error is raised (as it would have been when run one by one)."""
    futures = [_POOL.submit(t) for t in tasks]
    return [f.result() for f in futures]


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
            # Defensive - the route already validates this via a Query pattern constraint; a
            # service-level caller gets the same guarantee rather than an obscure downstream error.
            raise ValidationError(f"range must be one of {sorted(_DATE_RANGES)}.")

        now = datetime.now(timezone.utc)
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        since, until = _range_bounds(range_key, now)
        since_iso, until_iso = _iso_or_none(since), _iso_or_none(until)

        # Step 1: the few lookups the counts below depend on.
        recipient_member_id, statuses, members = _run_all(
            [
                lambda: self._current_member_id(workspace_id),
                lambda: self._statuses.list_for_workspace(workspace_id),
                lambda: self._members.list_active(workspace_id),
            ]
        )
        default_status = next((st for st in statuses if st.get("is_default")), None)

        # Step 2: every count, side by side. Run one after another, each waiting on a network round
        # trip to Supabase, they took seconds; together they take about as long as the slowest few.
        fixed = [
            lambda: self._leads.list_for_workspace(workspace_id, limit=1)[1],  # 0 total_active_leads
            lambda: self._leads.list_for_workspace(workspace_id, is_customer=True, limit=1)[1],  # 1 customers
            lambda: self._follow_ups.list_for_workspace(workspace_id, status="pending", limit=1)[1],  # 2
            lambda: self._follow_ups.list_for_workspace(workspace_id, status="completed", limit=1)[1],  # 3
            lambda: self._calls.list_for_workspace(workspace_id, limit=1)[1],  # 4 total_calls
            lambda: self._notifications.list_for_workspace(
                workspace_id, recipient_member_id, is_read=False, limit=1
            )[1],  # 5 unread_notifications
            # No default lead status configured (an admin never set one): "new leads" has nothing
            # to count against rather than guessing a fallback definition.
            (lambda: self._leads.list_for_workspace(workspace_id, status_id=default_status["id"], limit=1)[1])
            if default_status
            else (lambda: 0),  # 6 new_leads
            lambda: self._follow_ups.count_overdue(workspace_id, _iso(now)),  # 7
            lambda: self._calls.count_since(workspace_id, _iso(today_start)),  # 8 todays_calls
            # Period analytics (Phase 17)
            lambda: self._leads.list_for_workspace(workspace_id, created_from=since, limit=1)[1],  # 9
            lambda: self._leads.count_converted(workspace_id, since=since_iso, until=until_iso),  # 10
            lambda: self._calls.count_filtered(
                workspace_id, since=since_iso, until=until_iso, states=["CONNECTED", "ENDED"]
            ),  # 11
            lambda: self._calls.count_filtered(workspace_id, since=since_iso, until=until_iso, states=["ENDED"]),  # 12
            lambda: self._follow_ups.count_completed(workspace_id, since=since_iso, until=until_iso),  # 13
        ]
        per_status = [
            (lambda st=st: self._leads.list_for_workspace(
                workspace_id, status_id=st["id"], created_from=since, limit=1
            )[1])
            for st in statuses
        ]
        per_member = []
        for member in members:
            member_id = member["id"]
            per_member += [
                (lambda mid=member_id: self._leads.list_for_workspace(
                    workspace_id, assigned_member_id=mid, created_from=since, limit=1
                )[1]),
                (lambda mid=member_id: self._calls.count_filtered(
                    workspace_id, agent_member_id=mid, since=since_iso, until=until_iso
                )),
                (lambda mid=member_id: self._follow_ups.count_completed(
                    workspace_id, assigned_member_id=mid, since=since_iso, until=until_iso
                )),
            ]
        results = _run_all(fixed + per_status + per_member)
        fixed_results = results[: len(fixed)]
        status_counts = results[len(fixed) : len(fixed) + len(per_status)]
        member_counts = results[len(fixed) + len(per_status) :]

        leads_created, converted = fixed_results[9], fixed_results[10]
        return {
            "total_active_leads": fixed_results[0],
            "new_leads": fixed_results[6],
            "customers": fixed_results[1],
            "pending_follow_ups": fixed_results[2],
            "overdue_follow_ups": fixed_results[7],
            "completed_follow_ups": fixed_results[3],
            "total_calls": fixed_results[4],
            "todays_calls": fixed_results[8],
            "unread_notifications": fixed_results[5],
            "range": range_key,
            "leads_created_in_range": leads_created,
            "converted_leads_in_range": converted,
            "conversion_rate": (converted / leads_created) if leads_created > 0 else 0.0,
            "calls_connected_in_range": fixed_results[11],
            "calls_completed_in_range": fixed_results[12],
            "completed_follow_ups_in_range": fixed_results[13],
            # Pipeline distribution: of the leads created in the window, how many sit in each stage.
            "leads_by_status": [{"status": st, "count": c} for st, c in zip(statuses, status_counts)],
            "team_productivity": self._productivity_rows(members, member_counts),
        }

    @staticmethod
    def _productivity_rows(members: list[dict[str, Any]], counts: list[int]) -> list[dict[str, Any]]:
        """Per-member productivity (Phase 17). No manager-only gate here: every count ran through
        this request's own RLS-scoped client, so a team_mate's counts for every OTHER member come
        back zero automatically; dropping all-zero rows turns that into "a team_mate only ever sees
        their own row" without this code ever branching on role."""
        rows: list[dict[str, Any]] = []
        for i, member in enumerate(members):
            leads_count, calls_count, completed_count = counts[i * 3 : i * 3 + 3]
            if leads_count == 0 and calls_count == 0 and completed_count == 0:
                continue
            rows.append(
                {
                    "member": {"id": member["id"], "full_name": member.get("full_name")},
                    "leads_count": leads_count,
                    "calls_count": calls_count,
                    "completed_follow_ups_count": completed_count,
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

        # Nine independent reads: side by side instead of one after another.
        (
            (calls, calls_total),
            follow_ups,
            interactions,
            allocations,
            (notifications, notifications_total),
            (_, follow_ups_total),
            interactions_total,
            allocations_total,
        ) = _run_all(
            [
                lambda: self._calls.list_for_workspace(workspace_id, limit=window, offset=0),
                lambda: self._follow_ups.list_recent_for_workspace(workspace_id, limit=window),
                lambda: self._interactions.list_recent_for_workspace(workspace_id, limit=window),
                lambda: self._allocations.list_recent_for_workspace(workspace_id, limit=window),
                lambda: self._notifications.list_for_workspace(workspace_id, recipient_member_id, limit=window, offset=0),
                lambda: self._follow_ups.list_for_workspace(workspace_id, limit=1),
                lambda: self._interactions.count_for_workspace(workspace_id),
                lambda: self._allocations.count_for_workspace(workspace_id),
            ]
        )

        # follow_ups/interactions/allocations don't have their own
        # `list_for_workspace`-with-count method the way calls does
        # (list_recent_for_workspace, added just above, is
        # bounded-window-only, matching its lead-scoped sibling) — reuse
        # the existing `list_for_workspace(limit=1)` trick for follow-ups'
        # total, and the count_for_workspace() added alongside
        # list_recent_for_workspace for interactions/allocations.

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
