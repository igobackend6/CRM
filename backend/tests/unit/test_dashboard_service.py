from uuid import uuid4

from app.services.dashboard.service import DashboardService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
STATUS_ID = str(uuid4())


def _lead_row(**overrides):
    row = {
        "id": str(uuid4()),
        "workspace_id": str(WORKSPACE_ID),
        "name": "Acme Corp",
        "phone": None,
        "email": None,
        "priority": "medium",
        "status_id": STATUS_ID,
        "source_id": None,
        "assigned_member_id": MEMBER_ID,
        "created_by_member_id": MEMBER_ID,
        "is_customer": False,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }
    row.update(overrides)
    return row


def _client(**overrides):
    """Every call in DashboardService.get_summary() that hits a given
    table (e.g. two differently-filtered `leads` queries for
    total_active_leads vs customers) shares the *same* configured
    FakeResponse for that table name — FakeSupabaseClient records calls
    but doesn't actually apply `.eq()`/`.limit()` filters. This proves
    the service builds and wires the right queries (§ "Backend Rules" —
    workspace-scoped, RLS does the real filtering), not that Postgres
    itself would return different numbers for different filters — the
    fake was never meant to prove that, matching every other service
    test in this codebase. Tests below that need genuinely distinct
    counts use distinct *tables* (calls vs follow_ups vs interactions vs
    allocations vs notifications), where the fake's per-table fixtures
    really are independent.
    """
    table_responses = {
        "lead_statuses": FakeResponse(data=[{"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}]),
        "leads": FakeResponse(data=[_lead_row()], count=3),
        "follow_ups": FakeResponse(data=[], count=2),
        "calls": FakeResponse(data=[], count=5),
        "notifications": FakeResponse(data=[], count=1),
        "interactions": FakeResponse(data=[], count=0),
        "allocations": FakeResponse(data=[], count=0),
        "workspace_members": FakeResponse(data=[]),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {"current_member_id": MEMBER_ID}
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


# ---- get_summary ----


_PHASE_11_FIELDS = {
    "total_active_leads",
    "new_leads",
    "customers",
    "pending_follow_ups",
    "overdue_follow_ups",
    "completed_follow_ups",
    "total_calls",
    "todays_calls",
    "unread_notifications",
}

_PHASE_17_FIELDS = {
    "range",
    "leads_created_in_range",
    "converted_leads_in_range",
    "conversion_rate",
    "calls_connected_in_range",
    "calls_completed_in_range",
    "completed_follow_ups_in_range",
    "leads_by_status",
    "team_productivity",
}


def test_get_summary_returns_all_nine_metrics_as_ints():
    client = _client()
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    # Phase 17 §"existing dashboard compatibility": the original 9
    # fields are still present, still plain ints, still computed
    # exactly as before — extending the response is additive, not a
    # breaking change to what Phase 11 already shipped.
    assert _PHASE_11_FIELDS <= set(summary.keys())
    assert all(isinstance(summary[k], int) for k in _PHASE_11_FIELDS)
    # Every leads-table field shares the same fixture count (see _client's
    # docstring) — this is the fake's own limitation, not a bug.
    assert summary["total_active_leads"] == 3
    assert summary["customers"] == 3
    assert summary["new_leads"] == 3
    assert summary["total_calls"] == 5
    assert summary["todays_calls"] == 5
    assert summary["unread_notifications"] == 1


def test_get_summary_also_returns_the_phase_17_period_analytics_fields():
    client = _client()
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert set(summary.keys()) == _PHASE_11_FIELDS | _PHASE_17_FIELDS
    assert summary["range"] == "all"
    assert isinstance(summary["conversion_rate"], float)
    assert isinstance(summary["leads_by_status"], list)
    assert isinstance(summary["team_productivity"], list)


def test_get_summary_resolves_the_recipient_server_side_never_from_the_client():
    client = _client()
    service = DashboardService(client)

    service.get_summary(WORKSPACE_ID)

    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls


def test_get_summary_new_leads_is_zero_without_a_default_status_configured():
    client = _client(table_responses={"lead_statuses": FakeResponse(data=[])})
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert summary["new_leads"] == 0
    # Unaffected — this branch short-circuits before ever querying leads.
    assert summary["total_active_leads"] == 3


def test_get_summary_on_an_empty_workspace_returns_all_zeros():
    client = _client(
        table_responses={
            "leads": FakeResponse(data=[], count=0),
            "follow_ups": FakeResponse(data=[], count=0),
            "calls": FakeResponse(data=[], count=0),
            "notifications": FakeResponse(data=[], count=0),
            "lead_statuses": FakeResponse(data=[]),
        }
    )
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert all(summary[k] == 0 for k in _PHASE_11_FIELDS)
    assert summary["range"] == "all"
    assert summary["conversion_rate"] == 0.0
    assert summary["leads_by_status"] == []
    assert summary["team_productivity"] == []


# ---- get_recent_activity ----


def _call_row(**overrides):
    row = {
        "id": str(uuid4()),
        "lead_id": str(uuid4()),
        "agent_member_id": MEMBER_ID,
        "direction": "outbound",
        "state": "ENDED",
        "duration_seconds": 60,
        "notes": None,
        "started_at": "2026-01-01T09:00:00Z",
    }
    row.update(overrides)
    return row


def _follow_up_row(**overrides):
    row = {
        "id": str(uuid4()),
        "lead_id": str(uuid4()),
        "type": "call",
        "status": "pending",
        "due_at": "2026-01-05T09:00:00Z",
        "notes": None,
        "created_by_member_id": MEMBER_ID,
        "created_at": "2026-01-01T08:00:00Z",
    }
    row.update(overrides)
    return row


def _interaction_row(**overrides):
    row = {
        "id": str(uuid4()),
        "type": "note",
        "payload": {"text": "Called and left a voicemail"},
        "actor_member_id": MEMBER_ID,
        "created_at": "2026-01-01T07:00:00Z",
    }
    row.update(overrides)
    return row


def _allocation_row(**overrides):
    row = {
        "id": str(uuid4()),
        "assigned_member_id": MEMBER_ID,
        "assigned_by_member_id": MEMBER_ID,
        "status": "new",
        "assigned_at": "2026-01-01T06:00:00Z",
        "created_at": "2026-01-01T06:00:00Z",
    }
    row.update(overrides)
    return row


def _notification_row(**overrides):
    row = {
        "id": str(uuid4()),
        "type": "lead_assigned",
        "title": "Lead assigned to you",
        "body": "Acme Corp",
        "related_entity_type": "lead",
        "related_entity_id": str(uuid4()),
        "is_read": False,
        "read_at": None,
        "created_at": "2026-01-01T10:00:00Z",
    }
    row.update(overrides)
    return row


def test_get_recent_activity_merges_all_five_sources_sorted_by_recency():
    client = _client(
        table_responses={
            "calls": FakeResponse(data=[_call_row(started_at="2026-01-01T09:00:00Z")], count=1),
            "follow_ups": FakeResponse(data=[_follow_up_row(created_at="2026-01-01T08:00:00Z")], count=1),
            "interactions": FakeResponse(data=[_interaction_row(created_at="2026-01-01T07:00:00Z")], count=1),
            "allocations": FakeResponse(data=[_allocation_row(created_at="2026-01-01T06:00:00Z")], count=1),
            "notifications": FakeResponse(data=[_notification_row(created_at="2026-01-01T10:00:00Z")], count=1),
        }
    )
    service = DashboardService(client)

    items, total = service.get_recent_activity(WORKSPACE_ID, limit=20, offset=0)

    assert total == 5
    assert [i["type"] for i in items] == ["notification", "call", "follow_up", "note", "allocation"]
    # id is prefixed by source table, same contract as Customer 360's
    # timeline (TimelineItemOut's own docstring).
    assert items[0]["id"].startswith("notification:")
    assert items[1]["id"].startswith("call:")


def test_get_recent_activity_notification_item_uses_the_title_as_its_summary():
    client = _client(
        table_responses={
            "notifications": FakeResponse(data=[_notification_row(title="Follow-up reassigned to you")], count=1),
            "calls": FakeResponse(data=[], count=0),
            "follow_ups": FakeResponse(data=[], count=0),
            "interactions": FakeResponse(data=[], count=0),
            "allocations": FakeResponse(data=[], count=0),
        }
    )
    service = DashboardService(client)

    items, _ = service.get_recent_activity(WORKSPACE_ID, limit=20, offset=0)

    assert items[0]["summary"] == "Follow-up reassigned to you"
    assert items[0]["actor_member"] is None  # notifications have no actor concept


def test_get_recent_activity_paginates():
    rows = [_call_row(started_at=f"2026-01-01T0{i}:00:00Z") for i in range(1, 6)]
    client = _client(
        table_responses={
            "calls": FakeResponse(data=rows, count=5),
            "follow_ups": FakeResponse(data=[], count=0),
            "interactions": FakeResponse(data=[], count=0),
            "allocations": FakeResponse(data=[], count=0),
            "notifications": FakeResponse(data=[], count=0),
        }
    )
    service = DashboardService(client)

    page, total = service.get_recent_activity(WORKSPACE_ID, limit=2, offset=0)

    assert total == 5
    assert len(page) == 2


# ---- Phase 17 — period analytics ----


def _member_row(member_id: str, full_name: str = "Jamie Rep"):
    return {"id": member_id, "profile": {"full_name": full_name}}


def test_get_summary_rejects_an_unknown_range_key():
    import pytest

    from app.core.exceptions import ValidationError

    client = _client()
    service = DashboardService(client)

    with pytest.raises(ValidationError):
        service.get_summary(WORKSPACE_ID, range_key="last_year")


def test_conversion_rate_is_zero_when_no_leads_were_created_in_range():
    """Zero-denominator guard (Phase 17 §"zero-denominator conversion
    rate") — an empty/new workspace (or a range with no activity) must
    never divide by zero."""
    client = _client(table_responses={"leads": FakeResponse(data=[], count=0)})
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert summary["leads_created_in_range"] == 0
    assert summary["converted_leads_in_range"] == 0
    assert summary["conversion_rate"] == 0.0


def test_conversion_rate_divides_converted_by_created():
    """`FakeSupabaseClient` shares one configured response per *table*
    regardless of filters (see `_client`'s own docstring), so
    `leads_created_in_range` (list_for_workspace) and
    `converted_leads_in_range` (count_converted) — both `leads` queries —
    resolve to the same configured count here. This still proves the
    division itself is wired correctly (denominator > 0 branch); it
    cannot prove Postgres would return two *different* numbers for two
    differently-filtered queries — same limitation the rest of this file
    already documents and works around by using distinct tables."""
    client = _client(table_responses={"leads": FakeResponse(data=[_lead_row()], count=4)})
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert summary["leads_created_in_range"] == 4
    assert summary["converted_leads_in_range"] == 4
    assert summary["conversion_rate"] == 1.0


def test_leads_by_status_has_one_row_per_workspace_status():
    statuses = [
        {"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True},
        {"id": str(uuid4()), "name": "Won", "code": "won", "sort_order": 20, "stage": "closed_won", "is_default": False},
    ]
    client = _client(table_responses={"lead_statuses": FakeResponse(data=statuses)})
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert len(summary["leads_by_status"]) == 2
    assert {row["status"]["code"] for row in summary["leads_by_status"]} == {"new", "won"}
    assert all(isinstance(row["count"], int) for row in summary["leads_by_status"])


def test_leads_by_status_is_empty_when_the_workspace_has_no_statuses():
    client = _client(table_responses={"lead_statuses": FakeResponse(data=[])})
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert summary["leads_by_status"] == []
    # An unconfigured workspace has neither statuses nor a default —
    # new_leads must still degrade to 0, not raise.
    assert summary["new_leads"] == 0


def test_calls_connected_and_completed_are_present_as_ints():
    client = _client(table_responses={"calls": FakeResponse(data=[], count=7)})
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert summary["calls_connected_in_range"] == 7
    assert summary["calls_completed_in_range"] == 7


def test_team_productivity_omits_members_with_no_activity():
    other_member = str(uuid4())
    client = _client(
        table_responses={
            "workspace_members": FakeResponse(data=[_member_row(MEMBER_ID, "Active Member"), _member_row(other_member, "Idle Member")]),
            "leads": FakeResponse(data=[], count=0),
            "calls": FakeResponse(data=[], count=0),
            "follow_ups": FakeResponse(data=[], count=0),
        }
    )
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert summary["team_productivity"] == []


def test_team_productivity_includes_members_with_activity():
    client = _client(
        table_responses={
            "workspace_members": FakeResponse(data=[_member_row(MEMBER_ID, "Jamie Rep")]),
            "leads": FakeResponse(data=[_lead_row()], count=3),
            "calls": FakeResponse(data=[], count=2),
            "follow_ups": FakeResponse(data=[], count=1),
        }
    )
    service = DashboardService(client)

    summary = service.get_summary(WORKSPACE_ID)

    assert len(summary["team_productivity"]) == 1
    row = summary["team_productivity"][0]
    assert row["member"]["id"] == MEMBER_ID
    assert row["member"]["full_name"] == "Jamie Rep"
    assert row["leads_count"] == 3
    assert row["calls_count"] == 2
    assert row["completed_follow_ups_count"] == 1


def test_range_default_is_all_and_is_echoed_back():
    client = _client()
    service = DashboardService(client)

    assert service.get_summary(WORKSPACE_ID)["range"] == "all"
    assert service.get_summary(WORKSPACE_ID, range_key="today")["range"] == "today"
    assert service.get_summary(WORKSPACE_ID, range_key="this_week")["range"] == "this_week"
    assert service.get_summary(WORKSPACE_ID, range_key="this_month")["range"] == "this_month"


def test_get_recent_activity_on_an_empty_workspace_returns_no_items():
    client = _client(
        table_responses={
            "calls": FakeResponse(data=[], count=0),
            "follow_ups": FakeResponse(data=[], count=0),
            "interactions": FakeResponse(data=[], count=0),
            "allocations": FakeResponse(data=[], count=0),
            "notifications": FakeResponse(data=[], count=0),
        }
    )
    service = DashboardService(client)

    items, total = service.get_recent_activity(WORKSPACE_ID, limit=20, offset=0)

    assert items == []
    assert total == 0
