from uuid import uuid4

import pytest

from app.core.exceptions import ValidationError
from app.services.reports.service import ReportService
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
OTHER_MEMBER_ID = str(uuid4())
STATUS_ID = str(uuid4())
LOST_STATUS_ID = str(uuid4())
SOURCE_ID = str(uuid4())
OUTCOME_ID = str(uuid4())


def _status_row(**overrides):
    row = {"id": STATUS_ID, "name": "New", "code": "new", "sort_order": 10, "stage": "in_progress", "is_default": True}
    row.update(overrides)
    return row


def _source_row(**overrides):
    row = {"id": SOURCE_ID, "name": "Website", "code": "website", "is_default": False}
    row.update(overrides)
    return row


def _outcome_row(**overrides):
    row = {"id": OUTCOME_ID, "name": "Connected", "code": "connected", "is_positive": True, "is_default": True}
    row.update(overrides)
    return row


def _client(**overrides):
    """Same fake-client limitation as test_dashboard_service.py's own
    `_client` docstring: every call against one table shares that
    table's single configured fixture, regardless of the filters this
    service actually applied (e.g. every `calls_by_outcome` row, one
    query per outcome, reads the same `calls` fixture) — this proves
    ReportService builds and wires the right queries/RPCs, not that
    Postgres would return different numbers per outcome. Tests below
    that need genuinely distinct values use distinct tables."""
    table_responses = {
        "lead_statuses": FakeResponse(data=[_status_row(), _status_row(id=LOST_STATUS_ID, name="Lost", code="lost", stage="closed_lost", is_default=False)]),
        "lead_sources": FakeResponse(data=[_source_row()]),
        "call_outcomes": FakeResponse(data=[_outcome_row()]),
        "leads": FakeResponse(data=[], count=3),
        "follow_ups": FakeResponse(data=[], count=2),
        "calls": FakeResponse(data=[], count=5),
        "workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Jamie Rep"}}]),
    }
    table_responses.update(overrides.pop("table_responses", {}))
    rpc_responses = {
        "current_member_id": MEMBER_ID,
        "report_call_duration_stats": [{"total_talk_seconds": 600, "average_call_seconds": 120.0}],
    }
    rpc_responses.update(overrides.pop("rpc_responses", {}))
    return FakeSupabaseClient(table_responses=table_responses, rpc_responses=rpc_responses)


# ---- personal report ----


def test_personal_report_returns_all_four_sections():
    service = ReportService(_client())

    report = service.get_personal_report(WORKSPACE_ID, range_key="all_time")

    assert set(report.keys()) == {"range", "since", "until", "calls", "follow_ups", "leads", "pipeline"}
    assert report["range"] == "all_time"
    assert report["since"] is None and report["until"] is None


def test_personal_report_resolves_the_caller_server_side():
    client = _client()
    service = ReportService(client)

    service.get_personal_report(WORKSPACE_ID, range_key="all_time")

    assert ("current_member_id", {"p_workspace_id": str(WORKSPACE_ID)}) in client.rpc_calls


def test_personal_report_call_metrics_shape():
    service = ReportService(_client())

    report = service.get_personal_report(WORKSPACE_ID, range_key="all_time")
    calls = report["calls"]

    assert calls["total_calls"] == 5
    assert calls["connected_calls"] == 5  # same shared "calls" fixture — see _client's docstring
    assert len(calls["calls_by_outcome"]) == 1
    assert calls["calls_by_outcome"][0]["outcome"]["id"] == OUTCOME_ID
    assert calls["total_talk_time_seconds"] == 600
    assert calls["average_call_duration_seconds"] == 120.0


def test_personal_report_follow_up_metrics_shape():
    service = ReportService(_client())

    report = service.get_personal_report(WORKSPACE_ID, range_key="all_time")
    follow_ups = report["follow_ups"]

    assert set(follow_ups.keys()) == {
        "total_follow_ups",
        "pending_follow_ups",
        "completed_follow_ups",
        "cancelled_follow_ups",
        "overdue_follow_ups",
    }
    assert all(isinstance(v, int) for v in follow_ups.values())


def test_personal_report_conversion_rate_is_zero_when_no_leads_assigned():
    client = _client(table_responses={"leads": FakeResponse(data=[], count=0)})
    service = ReportService(client)

    report = service.get_personal_report(WORKSPACE_ID, range_key="all_time")

    assert report["leads"]["conversion_rate"] == 0.0
    assert report["leads"]["leads_assigned"] == 0


def test_personal_report_pipeline_snapshot_includes_both_statuses():
    service = ReportService(_client())

    report = service.get_personal_report(WORKSPACE_ID, range_key="all_time")
    pipeline = report["pipeline"]

    assert len(pipeline["leads_by_status"]) == 2
    assert pipeline["active_pipeline_count"] >= 0  # floor-guarded, never negative


def test_personal_report_rejects_an_unknown_range():
    service = ReportService(_client())

    with pytest.raises(ValidationError):
        service.get_personal_report(WORKSPACE_ID, range_key="last_year")


def test_personal_report_custom_range_requires_both_bounds():
    service = ReportService(_client())

    with pytest.raises(ValidationError):
        service.get_personal_report(WORKSPACE_ID, range_key="custom")


# ---- team report ----


def test_team_report_returns_one_row_per_active_member():
    client = _client(table_responses={"workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Jamie Rep"}}, {"id": OTHER_MEMBER_ID, "profile": {"full_name": "Alex Rep"}}])})
    service = ReportService(client)

    report = service.get_team_report(WORKSPACE_ID, range_key="all_time")

    assert report["total"] == 2
    assert len(report["items"]) == 2
    assert set(report["totals"].keys()) == {
        "leads_assigned",
        "leads_converted",
        "conversion_rate",
        "calls",
        "connected_calls",
        "talk_time_seconds",
        "completed_follow_ups",
        "pending_follow_ups",
    }


def test_team_report_totals_conversion_rate_is_computed_from_summed_totals_not_averaged():
    client = _client(table_responses={"workspace_members": FakeResponse(data=[{"id": MEMBER_ID, "profile": {"full_name": "Jamie Rep"}}, {"id": OTHER_MEMBER_ID, "profile": {"full_name": "Alex Rep"}}])})
    service = ReportService(client)

    report = service.get_team_report(WORKSPACE_ID, range_key="all_time")

    # Every member row shares the same fixture-derived leads_assigned (3)
    # and leads_converted (both leads/calls default counts) — the point
    # here is just that totals.conversion_rate == total_converted /
    # total_assigned, not an average of the per-row rates.
    totals = report["totals"]
    if totals["leads_assigned"] > 0:
        assert totals["conversion_rate"] == pytest.approx(totals["leads_converted"] / totals["leads_assigned"])
    else:
        assert totals["conversion_rate"] == 0.0


def test_team_report_paginates_bounded_by_limit_and_offset():
    members = [{"id": str(uuid4()), "profile": {"full_name": f"Rep {i}"}} for i in range(5)]
    client = _client(table_responses={"workspace_members": FakeResponse(data=members)})
    service = ReportService(client)

    report = service.get_team_report(WORKSPACE_ID, range_key="all_time", limit=2, offset=0)

    assert report["total"] == 5
    assert len(report["items"]) == 2
    assert report["limit"] == 2
    assert report["offset"] == 0


def test_team_report_on_an_empty_workspace_returns_no_rows_and_zero_totals():
    client = _client(table_responses={"workspace_members": FakeResponse(data=[])})
    service = ReportService(client)

    report = service.get_team_report(WORKSPACE_ID, range_key="all_time")

    assert report["items"] == []
    assert report["total"] == 0
    assert report["totals"]["conversion_rate"] == 0.0


# ---- pipeline report ----


def test_pipeline_report_returns_a_percentage_per_status_summing_near_100():
    service = ReportService(_client())

    report = service.get_pipeline_report(WORKSPACE_ID, range_key="all_time")

    assert len(report["leads_by_status"]) == 2
    total_pct = sum(item["percentage"] for item in report["leads_by_status"])
    assert total_pct == pytest.approx(100.0, abs=0.5)


def test_pipeline_report_percentage_is_zero_on_an_empty_workspace():
    client = _client(table_responses={"leads": FakeResponse(data=[], count=0)})
    service = ReportService(client)

    report = service.get_pipeline_report(WORKSPACE_ID, range_key="all_time")

    assert all(item["percentage"] == 0.0 for item in report["leads_by_status"])
    assert all(item["percentage"] == 0.0 for item in report["priority_distribution"])


def test_pipeline_report_source_performance_includes_every_workspace_source():
    service = ReportService(_client())

    report = service.get_pipeline_report(WORKSPACE_ID, range_key="all_time")

    assert len(report["source_performance"]) == 1
    assert report["source_performance"][0]["source"]["id"] == SOURCE_ID


def test_pipeline_report_priority_distribution_covers_all_four_priorities():
    service = ReportService(_client())

    report = service.get_pipeline_report(WORKSPACE_ID, range_key="all_time")

    assert {item["priority"] for item in report["priority_distribution"]} == {"low", "medium", "high", "urgent"}


def test_pipeline_report_rejects_an_unknown_range():
    service = ReportService(_client())

    with pytest.raises(ValidationError):
        service.get_pipeline_report(WORKSPACE_ID, range_key="not_a_range")


# ---- Analytics hub: get_call_trends ----

from datetime import datetime, timedelta, timezone  # noqa: E402


def _trend_service(rows, *, captured=None):
    service = ReportService(_client())

    def fake_list_for_trends(workspace_id, **kwargs):
        if captured is not None:
            captured.update(kwargs)
        return rows

    service._calls.list_for_trends = fake_list_for_trends
    return service


def _call(started_at, *, lead="lead-a", duration=60):
    return {"started_at": started_at, "state": "ENDED", "lead_id": lead, "duration_seconds": duration}


# A user in IST (UTC+5:30) asking for "today": local midnight 2026-09-24 is
# 2026-09-23T18:30Z, and the window is one local day.
_IST_MIDNIGHT = datetime(2026, 9, 23, 18, 30, tzinfo=timezone.utc)


def _day_trends(service, **overrides):
    kwargs = {
        "since": _IST_MIDNIGHT,
        "until": _IST_MIDNIGHT + timedelta(days=1),
        "granularity": "hour",
        "direction": "all",
    }
    kwargs.update(overrides)
    return service.get_call_trends(WORKSPACE_ID, **kwargs)


def test_call_trends_zero_fills_one_bucket_per_hour_of_the_window():
    result = _day_trends(_trend_service([]))

    assert len(result["buckets"]) == 24
    assert all(b["calls"] == 0 and b["talk_time_seconds"] == 0 for b in result["buckets"])
    assert result["buckets"][0]["start"] == _IST_MIDNIGHT
    assert result["buckets"][23]["start"] == _IST_MIDNIGHT + timedelta(hours=23)
    assert result["total_calls"] == 0


def test_call_trends_buckets_are_counted_from_since_so_they_follow_the_users_local_hours():
    """03:15 UTC is 08:45 IST — local hour 8 — even though it's UTC hour 3."""
    result = _day_trends(_trend_service([_call("2026-09-24T03:15:00+00:00")]))

    assert result["buckets"][8]["calls"] == 1
    assert sum(b["calls"] for b in result["buckets"]) == 1


def test_call_trends_day_granularity_over_a_week_gives_seven_buckets():
    week_start = datetime(2026, 9, 20, 18, 30, tzinfo=timezone.utc)  # Mon 21 Sep, IST midnight
    service = _trend_service([_call("2026-09-22T10:00:00+00:00")])  # Tue 21 Sep 15:30 IST

    result = service.get_call_trends(
        WORKSPACE_ID, since=week_start, until=week_start + timedelta(days=7), granularity="day", direction="all"
    )

    assert len(result["buckets"]) == 7
    assert result["buckets"][1]["calls"] == 1


def test_call_trends_sums_talk_time_and_treats_missing_duration_as_zero():
    rows = [
        # All inside bucket 8 (02:30Z-03:30Z, i.e. 08:00-09:00 IST).
        _call("2026-09-24T02:40:00+00:00", duration=90),
        _call("2026-09-24T03:00:00+00:00", duration=30),
        _call("2026-09-24T03:20:00+00:00", duration=None),  # never connected
    ]

    result = _day_trends(_trend_service(rows))

    assert result["buckets"][8]["talk_time_seconds"] == 120
    assert result["total_talk_time_seconds"] == 120
    assert result["total_calls"] == 3


def test_call_trends_unique_leads_are_distinct_per_bucket_and_across_the_window():
    rows = [
        _call("2026-09-24T03:10:00+00:00", lead="a"),
        _call("2026-09-24T03:20:00+00:00", lead="a"),  # same lead, same bucket
        _call("2026-09-24T05:10:00+00:00", lead="a"),  # same lead, a later bucket
        _call("2026-09-24T05:20:00+00:00", lead="b"),
    ]

    result = _day_trends(_trend_service(rows))

    assert result["buckets"][8]["calls"] == 2
    assert result["buckets"][8]["unique_leads"] == 1
    assert result["buckets"][10]["unique_leads"] == 2
    # Window-wide distinct is NOT the sum of per-bucket distincts (1 + 2).
    assert result["unique_leads"] == 2
    assert result["total_calls"] == 4


def test_call_trends_ignores_rows_outside_the_window():
    rows = [_call("2026-09-23T18:00:00+00:00"), _call("2026-09-24T18:30:00+00:00")]

    assert _day_trends(_trend_service(rows))["total_calls"] == 0


def test_call_trends_passes_direction_through_only_when_not_all():
    captured = {}
    _day_trends(_trend_service([], captured=captured), direction="all")
    assert captured["direction"] is None

    _day_trends(_trend_service([], captured=captured), direction="outbound")
    assert captured["direction"] == "outbound"


def test_call_trends_queries_only_the_current_members_calls():
    captured = {}
    _day_trends(_trend_service([], captured=captured))

    assert captured["agent_member_id"] == MEMBER_ID


def test_call_trends_treats_a_naive_since_until_as_utc():
    since = datetime(2026, 9, 24, 0, 0)  # no tzinfo
    service = _trend_service([_call("2026-09-24T03:15:00+00:00")])

    result = service.get_call_trends(
        WORKSPACE_ID, since=since, until=since + timedelta(days=1), granularity="hour", direction="all"
    )

    assert result["buckets"][3]["calls"] == 1


@pytest.mark.parametrize(
    "overrides",
    [
        {"granularity": "week"},
        {"direction": "sideways"},
        {"until": _IST_MIDNIGHT},  # since == until
        {"until": _IST_MIDNIGHT - timedelta(hours=1)},  # since after until
        # 40 days of hourly buckets is 960 > the bucket ceiling.
        {"until": _IST_MIDNIGHT + timedelta(days=40)},
    ],
)
def test_call_trends_rejects_invalid_requests(overrides):
    with pytest.raises(ValidationError):
        _day_trends(_trend_service([]), **overrides)
