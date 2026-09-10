"""Regression test for a real crash found during Phase 21A physical-
device verification: uploading a document produced a `lead_documents.created_at`
whose fractional-seconds part PostgREST serialized with exactly 4
digits ('...06.4451+00:00') — Python 3.10's `datetime.fromisoformat`
only accepts 0, 3, or 6 fractional digits, so every service that
duplicated this same one-liner (`services/customer360/service.py`,
`calls/service.py`, `dashboard/service.py`, `followups/service.py`)
would crash the Activity/timeline endpoint with a bare 500 the moment
a timestamp happened to land on any other digit count.
"""

from datetime import datetime, timezone

import pytest

from app.core.timeparse import parse_supabase_datetime


def test_passes_through_an_already_parsed_datetime_unchanged():
    dt = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert parse_supabase_datetime(dt) is dt


@pytest.mark.parametrize(
    "digits",
    ["", "1", "12", "123", "1234", "12345", "123456"],
)
def test_parses_every_fractional_second_digit_count_postgrest_can_produce(digits):
    suffix = f".{digits}" if digits else ""
    value = f"2026-09-05T07:27:06{suffix}+00:00"
    parsed = parse_supabase_datetime(value)
    assert parsed.year == 2026 and parsed.second == 6


def test_parses_the_exact_value_that_crashed_the_activity_timeline():
    parsed = parse_supabase_datetime("2026-09-05T07:27:06.4451+00:00")
    assert parsed == datetime(2026, 9, 5, 7, 27, 6, 445100, tzinfo=timezone.utc)


def test_a_trailing_z_is_treated_as_utc():
    parsed = parse_supabase_datetime("2026-09-05T07:27:06.123Z")
    assert parsed.utcoffset().total_seconds() == 0


def test_a_negative_timezone_offset_combined_with_fractional_seconds_parses_correctly():
    parsed = parse_supabase_datetime("2026-09-05T07:27:06.42-05:30")
    assert parsed.microsecond == 420000
    assert parsed.utcoffset().total_seconds() == -5.5 * 3600


def test_no_fractional_seconds_at_all_still_parses():
    parsed = parse_supabase_datetime("2026-09-05T07:27:06+00:00")
    assert parsed.microsecond == 0
