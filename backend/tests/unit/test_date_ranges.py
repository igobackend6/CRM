from datetime import datetime, timedelta, timezone

import pytest

from app.core.date_ranges import REPORT_DATE_RANGES, resolve_report_range
from app.core.exceptions import ValidationError

# A fixed instant: Wednesday 2026-03-11 15:30 UTC — mid-week, mid-month,
# so "this_week"/"last_week"/"this_month"/"last_month" boundaries are
# all unambiguous (not accidentally sitting on a boundary themselves).
NOW = datetime(2026, 3, 11, 15, 30, tzinfo=timezone.utc)


def test_all_time_has_no_bounds():
    since, until = resolve_report_range("all_time", now=NOW)
    assert since is None and until is None


def test_today_starts_at_midnight_utc_and_is_open_ended():
    since, until = resolve_report_range("today", now=NOW)
    assert since == NOW.replace(hour=0, minute=0, second=0, microsecond=0)
    assert until is None


def test_yesterday_is_a_closed_full_day_window():
    since, until = resolve_report_range("yesterday", now=NOW)
    today_start = NOW.replace(hour=0, minute=0, second=0, microsecond=0)
    assert since == today_start - timedelta(days=1)
    assert until == today_start


def test_this_week_starts_monday_and_is_open_ended():
    since, until = resolve_report_range("this_week", now=NOW)
    assert since.weekday() == 0
    assert since.hour == 0
    assert until is None
    assert since <= NOW


def test_last_week_is_the_seven_days_before_this_week():
    since, until = resolve_report_range("last_week", now=NOW)
    this_week_since, _ = resolve_report_range("this_week", now=NOW)
    assert until == this_week_since
    assert since == this_week_since - timedelta(days=7)


def test_this_month_starts_on_the_first_and_is_open_ended():
    since, until = resolve_report_range("this_month", now=NOW)
    assert since == NOW.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    assert until is None


def test_last_month_is_the_full_previous_calendar_month():
    since, until = resolve_report_range("last_month", now=NOW)
    assert since == datetime(2026, 2, 1, tzinfo=timezone.utc)
    assert until == datetime(2026, 3, 1, tzinfo=timezone.utc)


def test_last_month_crosses_a_year_boundary_in_january():
    january_now = datetime(2026, 1, 15, tzinfo=timezone.utc)
    since, until = resolve_report_range("last_month", now=january_now)
    assert since == datetime(2025, 12, 1, tzinfo=timezone.utc)
    assert until == datetime(2026, 1, 1, tzinfo=timezone.utc)


def test_custom_range_uses_the_given_bounds():
    custom_since = datetime(2026, 1, 1, tzinfo=timezone.utc)
    custom_until = datetime(2026, 2, 1, tzinfo=timezone.utc)
    since, until = resolve_report_range("custom", now=NOW, custom_since=custom_since, custom_until=custom_until)
    assert since == custom_since and until == custom_until


def test_custom_range_requires_both_bounds():
    with pytest.raises(ValidationError):
        resolve_report_range("custom", now=NOW, custom_since=datetime(2026, 1, 1, tzinfo=timezone.utc))
    with pytest.raises(ValidationError):
        resolve_report_range("custom", now=NOW)


def test_custom_range_rejects_since_on_or_after_until():
    same = datetime(2026, 1, 1, tzinfo=timezone.utc)
    with pytest.raises(ValidationError):
        resolve_report_range("custom", now=NOW, custom_since=same, custom_until=same)
    with pytest.raises(ValidationError):
        resolve_report_range("custom", now=NOW, custom_since=same + timedelta(days=1), custom_until=same)


def test_unknown_range_is_rejected():
    with pytest.raises(ValidationError):
        resolve_report_range("last_year", now=NOW)


def test_every_documented_preset_is_a_member_of_the_range_set():
    assert REPORT_DATE_RANGES == {
        "today",
        "yesterday",
        "this_week",
        "last_week",
        "this_month",
        "last_month",
        "custom",
        "all_time",
    }
