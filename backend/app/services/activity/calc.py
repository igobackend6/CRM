from dataclasses import dataclass
from datetime import datetime, timedelta

from app.services.activity.intervals import Interval, clip, intersect, merge, subtract, total_seconds

# After a call ends the agent is "wrapping up" (logging the outcome, notes)
# for up to this long, or until they start another call or a break. The
# schema has no explicit wrap-up state (Runo's app has a dedicated one), so
# this is a defined, documented convention rather than a measurement: every
# call end opens a wrap-up window of at most this length.
WRAP_UP_WINDOW = timedelta(seconds=120)

# A call row with no ended_at is either genuinely in progress or stuck (the
# app died mid-call, so the end was never written). It occupies the agent
# from started_at until now, but never more than this — otherwise one stuck
# row would silently turn the rest of the day into "on a call".
IN_PROGRESS_CALL_CAP = timedelta(minutes=30)


@dataclass(frozen=True)
class CallSpan:
    """The parts of a `calls` row the maths needs."""

    started_at: datetime
    connected_at: datetime | None
    ended_at: datetime | None


@dataclass(frozen=True)
class ActivityTotals:
    login_seconds: int
    talk_seconds: int
    wrap_up_seconds: int
    break_seconds: int
    idle_seconds: int


def compute_activity(
    *,
    since: datetime,
    until: datetime,
    now: datetime,
    sessions: list[Interval],
    breaks: list[Interval],
    calls: list[CallSpan],
) -> ActivityTotals:
    """Login / talk / wrap-up / break / idle seconds for [since, until).

    Time is attributed in this priority order, so nothing is counted twice:

        on a call  >  on break  >  wrapping up  >  idle

    * login   - the union of the member's sessions, inside the window.
    * talk    - connected_at..ended_at of their calls. Reported in full: it
                is a fact about the calls table, not about whether the app
                happened to be reporting in at the time.
    * break   - explicit break intervals, minus time on a call.
    * wrap-up - WRAP_UP_WINDOW after each call ends, minus time on a call
                and on break (a next call, or a break starting, ends it).
    * idle    - logged in, but none of the above.

    Break, wrap-up and idle only exist while logged in (they are clipped to
    the sessions), so login = on-call + break + wrap-up + idle, where
    "on call" includes ringing/dialling time (started_at..ended_at) that is
    neither talk nor idle. Nothing happens in the future, so the window is
    cut off at [now].
    """
    hi = min(until, now)
    login = clip(sessions, since, hi)

    talk = clip([(c.connected_at, c.ended_at) for c in calls if c.connected_at and c.ended_at], since, hi)

    # "Busy" is the whole call: dialling and ringing as well as talking. A
    # call with no end yet is busy until now (capped, see above).
    busy = clip(
        [(c.started_at, c.ended_at or min(now, c.started_at + IN_PROGRESS_CALL_CAP)) for c in calls],
        since,
        hi,
    )

    on_break = subtract(clip(breaks, since, hi), busy)
    wrap_up = subtract(
        subtract(clip([(c.ended_at, c.ended_at + WRAP_UP_WINDOW) for c in calls if c.ended_at], since, hi), busy),
        on_break,
    )

    busy_in_login = intersect(busy, login)
    break_in_login = intersect(on_break, login)
    wrap_up_in_login = intersect(wrap_up, login)
    idle = subtract(login, merge(busy_in_login + break_in_login + wrap_up_in_login))

    return ActivityTotals(
        login_seconds=total_seconds(login),
        talk_seconds=total_seconds(talk),
        wrap_up_seconds=total_seconds(wrap_up_in_login),
        break_seconds=total_seconds(break_in_login),
        idle_seconds=total_seconds(idle),
    )
