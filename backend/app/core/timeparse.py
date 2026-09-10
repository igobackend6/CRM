import re
from datetime import datetime
from typing import Any

_FRACTIONAL_SECONDS = re.compile(r"\.(\d+)")


def parse_supabase_datetime(value: Any) -> datetime:
    """Parses a PostgREST-returned timestamp string (or passes through an
    already-parsed `datetime`) into a `datetime`.

    Postgres/PostgREST trims trailing zeros from the fractional-seconds
    part, so the same column can come back with anywhere from 0 to 6
    digits after the decimal point (e.g. `.4451` — 4 digits — is a real,
    observed value, not a hypothetical one: found live during Phase 21A
    device verification, when a lead document's `created_at` happened to
    land on exactly 4 significant fractional digits). Python 3.10's
    `datetime.fromisoformat` only accepts 0, 3, or 6 — anything else
    (like 4) raises `ValueError: Invalid isoformat string`, which is
    exactly what crashed the Activity timeline (customer360/service.py,
    calls/service.py, dashboard/service.py, followups/service.py all
    independently duplicated this same fragile one-liner). Padding the
    fractional part out to 6 digits before parsing accepts every digit
    count PostgREST can actually produce. A timezone offset never
    itself contains a literal `.`, so the first (and only) `.digits`
    match is always the fractional-seconds part, never ambiguous with
    a `+`/`-` offset later in the string.
    """
    if isinstance(value, datetime):
        return value

    text = str(value).replace("Z", "+00:00")
    text = _FRACTIONAL_SECONDS.sub(lambda m: "." + m.group(1)[:6].ljust(6, "0"), text, count=1)
    return datetime.fromisoformat(text)
