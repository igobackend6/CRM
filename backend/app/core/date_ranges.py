from datetime import datetime, timedelta, timezone

from app.core.exceptions import ValidationError

# Phase 21C §"Date Range Support" — the one canonical range implementation
# every report endpoint uses, deliberately separate from
# services/dashboard/service.py's own smaller `_DATE_RANGES`/`_range_bounds`
# (all/today/this_week/this_month) rather than extending that set: the
# dashboard's set is already shipped, tested, and referenced by its own
# report/back-compat guarantees (Phase 17 §"existing dashboard
# compatibility") — changing its meaning or accepted values is out of
# scope here (§"do not alter the existing Dashboard... unless necessary
# for reuse", and it isn't necessary: nothing about Reports requires
# touching Dashboard's route or service). Same UTC-only timezone
# behavior as that module: every `timestamptz` column in this schema is
# UTC, there is no per-user timezone preference anywhere
# (docs/architecture/database.md), so "yesterday"/"last week"/"last
# month" mean the calendar day/week/month in UTC, not the viewer's local
# calendar day. Documented here as a known limitation, not a silent
# assumption.
REPORT_DATE_RANGES = {
    "today",
    "yesterday",
    "this_week",
    "last_week",
    "this_month",
    "last_month",
    "custom",
    "all_time",
}


def resolve_report_range(
    range_key: str,
    *,
    now: datetime,
    custom_since: datetime | None = None,
    custom_until: datetime | None = None,
) -> tuple[datetime | None, datetime | None]:
    """`[since, until)` for one of `REPORT_DATE_RANGES`. `until=None`
    always means "open-ended, up to now" (matching
    dashboard/service.py's own convention) — every non-custom range
    below is deliberately bounded to a whole calendar unit rather than
    "up to now" for "yesterday"/"last week"/"last month" (those are
    fully-elapsed past periods, so `until` is their own period's end),
    while "today"/"this week"/"this month" stay open-ended (matching
    the dashboard's existing "up to now" reasoning for a period that's
    still in progress).
    """
    if range_key not in REPORT_DATE_RANGES:
        raise ValidationError(f"range must be one of {sorted(REPORT_DATE_RANGES)}.")

    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today_start - timedelta(days=today_start.weekday())  # Monday-start ISO week.
    month_start = today_start.replace(day=1)

    if range_key == "all_time":
        return None, None
    if range_key == "today":
        return today_start, None
    if range_key == "yesterday":
        return today_start - timedelta(days=1), today_start
    if range_key == "this_week":
        return week_start, None
    if range_key == "last_week":
        return week_start - timedelta(days=7), week_start
    if range_key == "this_month":
        return month_start, None
    if range_key == "last_month":
        last_month_end = month_start
        # First of the previous month, computed without a calendar
        # library dependency: step back one day from this month's
        # start (lands in the previous month), then jump to that day's
        # own month-start.
        last_month_start = (month_start - timedelta(days=1)).replace(day=1)
        return last_month_start, last_month_end

    # range_key == "custom"
    if custom_since is None or custom_until is None:
        raise ValidationError("Custom range requires both 'since' and 'until'.")
    if custom_since >= custom_until:
        raise ValidationError("'since' must be before 'until'.")
    return custom_since, custom_until


def utc_now() -> datetime:
    return datetime.now(timezone.utc)
