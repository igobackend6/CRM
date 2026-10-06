from datetime import datetime, timedelta, timezone

from app.services.activity.calc import WRAP_UP_WINDOW, CallSpan, compute_activity

# A working day: the window is 09:00-18:00 UTC and "now" is 17:00.
DAY_START = datetime(2026, 9, 24, 9, 0, tzinfo=timezone.utc)
DAY_END = DAY_START + timedelta(hours=9)
NOW = DAY_START + timedelta(hours=8)


def at(minutes: int) -> datetime:
    return DAY_START + timedelta(minutes=minutes)


def span(start: int, end: int):
    return (at(start), at(end))


def call(started: int, connected: int | None, ended: int | None) -> CallSpan:
    return CallSpan(
        started_at=at(started),
        connected_at=at(connected) if connected is not None else None,
        ended_at=at(ended) if ended is not None else None,
    )


def totals(*, sessions=(), breaks=(), calls=(), since=DAY_START, until=DAY_END, now=NOW):
    return compute_activity(since=since, until=until, now=now, sessions=list(sessions), breaks=list(breaks), calls=list(calls))


MIN = 60


def test_no_data_is_all_zero():
    result = totals()

    assert (result.login_seconds, result.talk_seconds, result.wrap_up_seconds, result.break_seconds, result.idle_seconds) == (0, 0, 0, 0, 0)


def test_a_session_alone_is_all_idle():
    result = totals(sessions=[span(0, 60)])

    assert result.login_seconds == 60 * MIN
    assert result.idle_seconds == 60 * MIN
    assert (result.talk_seconds, result.wrap_up_seconds, result.break_seconds) == (0, 0, 0)


def test_sessions_that_overlap_are_counted_once():
    assert totals(sessions=[span(0, 30), span(20, 50)]).login_seconds == 50 * MIN


def test_login_is_clipped_to_the_window():
    result = totals(sessions=[span(-120, 30)])  # began before 09:00

    assert result.login_seconds == 30 * MIN


def test_a_session_after_now_counts_for_nothing():
    """Nothing happens in the future: the window ends at now (17:00 = minute 480)."""
    result = totals(sessions=[span(470, 500)])

    assert result.login_seconds == 10 * MIN


class TestTalk:
    def test_talk_is_connected_to_ended(self):
        result = totals(sessions=[span(0, 120)], calls=[call(10, 11, 16)])  # rang 1 min, talked 5

        assert result.talk_seconds == 5 * MIN

    def test_ringing_time_is_not_talk_and_not_idle(self):
        result = totals(sessions=[span(0, 120)], calls=[call(10, 11, 16)])

        # 1 minute of ringing, then 5 of talk => 6 busy; wrap-up follows.
        busy = 6 * MIN
        assert result.idle_seconds == result.login_seconds - busy - result.wrap_up_seconds - result.break_seconds

    def test_a_call_that_never_connected_has_no_talk_time(self):
        result = totals(sessions=[span(0, 120)], calls=[call(10, None, 10 + 1)])

        assert result.talk_seconds == 0

    def test_talk_is_reported_in_full_even_if_no_session_was_recorded(self):
        """The calls table is the fact; a missed heartbeat must not erase it."""
        result = totals(sessions=[], calls=[call(10, 11, 21)])

        assert result.talk_seconds == 10 * MIN
        assert result.login_seconds == 0

    def test_talk_is_clipped_to_the_window(self):
        result = totals(calls=[call(-10, -5, 5)], since=DAY_START)  # 5 min before the window, 5 inside

        assert result.talk_seconds == 5 * MIN

    def test_overlapping_calls_count_once(self):
        result = totals(calls=[call(10, 10, 30), call(20, 20, 40)])

        assert result.talk_seconds == 30 * MIN


class TestWrapUp:
    def test_wrap_up_is_the_window_after_a_call_ends(self):
        result = totals(sessions=[span(0, 120)], calls=[call(10, 11, 21)])

        assert result.wrap_up_seconds == int(WRAP_UP_WINDOW.total_seconds())

    def test_wrap_up_stops_when_the_next_call_starts(self):
        # First call ends at 21; the next starts 30s later.
        second_start = 21 * MIN + 30
        second = CallSpan(started_at=at(0) + timedelta(seconds=second_start), connected_at=None, ended_at=None)

        result = totals(sessions=[span(0, 120)], calls=[call(10, 11, 21), second])

        assert result.wrap_up_seconds == 30

    def test_wrap_up_stops_when_a_break_starts(self):
        # Call ends at 21; a break begins at 21:45.
        break_start = at(21) + timedelta(seconds=45)
        result = totals(sessions=[span(0, 120)], calls=[call(10, 11, 21)], breaks=[(break_start, at(60))])

        assert result.wrap_up_seconds == 45

    def test_back_to_back_calls_only_wrap_up_after_the_gap(self):
        """Two calls with a 10-minute gap each get a full wrap-up window."""
        result = totals(sessions=[span(0, 120)], calls=[call(0, 1, 10), call(20, 21, 30)])

        assert result.wrap_up_seconds == 2 * int(WRAP_UP_WINDOW.total_seconds())

    def test_wrap_up_never_outlives_the_login(self):
        # The session closes 20s after the call ended.
        end = at(21) + timedelta(seconds=20)
        result = totals(sessions=[(at(0), end)], calls=[call(10, 11, 21)])

        assert result.wrap_up_seconds == 20

    def test_a_call_still_in_progress_has_no_wrap_up_yet(self):
        result = totals(sessions=[span(0, 120)], calls=[call(10, 11, None)])

        assert result.wrap_up_seconds == 0


class TestBreaks:
    def test_a_break_inside_the_login_counts(self):
        result = totals(sessions=[span(0, 120)], breaks=[span(30, 45)])

        assert result.break_seconds == 15 * MIN
        assert result.idle_seconds == (120 - 15) * MIN

    def test_a_break_outside_any_login_counts_for_nothing(self):
        """Break time is a share of login time, so it cannot exceed it."""
        result = totals(sessions=[span(0, 30)], breaks=[span(20, 60)])

        assert result.break_seconds == 10 * MIN

    def test_a_call_during_a_break_wins(self):
        """On a call is more real than a forgotten break."""
        result = totals(sessions=[span(0, 120)], breaks=[span(0, 60)], calls=[call(10, 10, 20)])

        assert result.talk_seconds == 10 * MIN
        assert result.break_seconds == 50 * MIN

    def test_overlapping_breaks_count_once(self):
        assert totals(sessions=[span(0, 120)], breaks=[span(10, 30), span(20, 40)]).break_seconds == 30 * MIN

    def test_an_open_break_runs_to_the_end_of_the_login(self):
        """The service closes an open break at now; the maths just clips it."""
        result = totals(sessions=[span(0, 60)], breaks=[(at(50), NOW)])

        assert result.break_seconds == 10 * MIN


class TestIdle:
    def test_idle_is_login_minus_everything_else(self):
        result = totals(
            sessions=[span(0, 120)],
            breaks=[span(60, 70)],
            calls=[call(10, 10, 20)],
        )

        assert result.login_seconds == 120 * MIN
        assert result.talk_seconds == 10 * MIN
        assert result.break_seconds == 10 * MIN
        assert result.wrap_up_seconds == 2 * MIN
        assert result.idle_seconds == (120 - 10 - 10 - 2) * MIN

    def test_the_parts_add_up_to_login_when_every_call_connected(self):
        """login = talk + wrap-up + break + idle (no ringing time)."""
        result = totals(
            sessions=[span(0, 200)],
            breaks=[span(100, 130)],
            calls=[call(10, 10, 25), call(40, 40, 42), call(150, 150, 160)],
        )

        parts = result.talk_seconds + result.wrap_up_seconds + result.break_seconds + result.idle_seconds
        assert parts == result.login_seconds

    def test_idle_is_never_negative(self):
        result = totals(sessions=[span(0, 5)], calls=[call(0, 0, 60)], breaks=[span(0, 60)])

        assert result.idle_seconds == 0


class TestIntegration:
    def test_a_realistic_day(self):
        """9:00 sign in; a 15-min break at 10:30; three calls; sign out 17:00."""
        result = totals(
            sessions=[span(0, 480)],
            breaks=[span(90, 105)],
            calls=[call(30, 31, 41), call(60, 60, 75), call(200, 201, 206)],
        )

        assert result.login_seconds == 480 * MIN
        assert result.talk_seconds == (10 + 15 + 5) * MIN
        assert result.break_seconds == 15 * MIN
        assert result.wrap_up_seconds == 3 * 2 * MIN
        # ringing: call 1 rang 1 minute, call 3 rang 1 minute.
        ringing = 2 * MIN
        assert result.idle_seconds == result.login_seconds - result.talk_seconds - ringing - result.wrap_up_seconds - result.break_seconds

    def test_a_split_day_with_a_gap_between_sessions(self):
        """Signed in 9-11 and 14-17; the gap is not login and not idle."""
        result = totals(sessions=[span(0, 120), span(300, 480)])

        assert result.login_seconds == (120 + 180) * MIN
        assert result.idle_seconds == result.login_seconds


class TestCallsWithoutAnEnd:
    def test_a_ringing_call_is_busy_from_when_it_started(self):
        """No ended_at yet: the agent is on that call, not idle."""
        result = totals(sessions=[span(0, 120)], calls=[call(10, None, None)], now=at(20))

        # Busy 10..20 (now); the login is clipped to now as well.
        assert result.login_seconds == 20 * MIN
        assert result.idle_seconds == 10 * MIN

    def test_a_stuck_call_only_occupies_up_to_the_cap(self):
        """A row that never ended must not swallow the rest of the day."""
        result = totals(sessions=[span(0, 480)], calls=[call(10, None, None)], now=NOW)

        assert result.login_seconds == 480 * MIN
        # Busy 10..40 only: exactly the 30-minute cap, not the remaining 470.
        assert result.idle_seconds == (480 - 30) * MIN

    def test_an_unended_call_has_no_talk_time_yet(self):
        assert totals(sessions=[span(0, 120)], calls=[call(10, 11, None)], now=at(30)).talk_seconds == 0
