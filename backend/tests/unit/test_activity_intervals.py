from datetime import datetime, timedelta, timezone

from app.services.activity.intervals import clip, intersect, merge, subtract, total_seconds

BASE = datetime(2026, 9, 24, 9, 0, tzinfo=timezone.utc)


def at(minutes: int) -> datetime:
    return BASE + timedelta(minutes=minutes)


def span(start: int, end: int):
    return (at(start), at(end))


def test_merge_sorts_and_combines_overlapping_spans():
    assert merge([span(20, 30), span(0, 10), span(5, 15)]) == [span(0, 15), span(20, 30)]


def test_merge_joins_spans_that_touch():
    assert merge([span(0, 10), span(10, 20)]) == [span(0, 20)]


def test_merge_keeps_a_span_swallowed_inside_another_as_one():
    assert merge([span(0, 60), span(10, 20)]) == [span(0, 60)]


def test_merge_drops_empty_and_inverted_spans():
    assert merge([span(5, 5), span(10, 3), span(20, 30)]) == [span(20, 30)]


def test_merge_of_nothing_is_nothing():
    assert merge([]) == []


def test_clip_restricts_to_the_window():
    assert clip([span(0, 100)], at(10), at(40)) == [span(10, 40)]


def test_clip_drops_spans_outside_the_window():
    assert clip([span(0, 5), span(50, 60)], at(10), at(40)) == []


def test_clip_keeps_the_part_of_a_span_that_straddles_an_edge():
    assert clip([span(0, 20), span(30, 60)], at(10), at(40)) == [span(10, 20), span(30, 40)]


def test_clip_with_an_empty_or_inverted_window_is_empty():
    assert clip([span(0, 100)], at(10), at(10)) == []
    assert clip([span(0, 100)], at(40), at(10)) == []


def test_intersect_returns_only_the_shared_time():
    assert intersect([span(0, 30)], [span(20, 50)]) == [span(20, 30)]


def test_intersect_handles_many_spans_on_each_side():
    a = [span(0, 10), span(20, 40), span(50, 60)]
    b = [span(5, 25), span(35, 55)]

    assert intersect(a, b) == [span(5, 10), span(20, 25), span(35, 40), span(50, 55)]


def test_intersect_of_disjoint_spans_is_empty():
    assert intersect([span(0, 10)], [span(10, 20)]) == []


def test_intersect_with_nothing_is_nothing():
    assert intersect([span(0, 10)], []) == []
    assert intersect([], [span(0, 10)]) == []


def test_subtract_removes_the_middle_of_a_span():
    assert subtract([span(0, 60)], [span(20, 30)]) == [span(0, 20), span(30, 60)]


def test_subtract_trims_the_ends():
    assert subtract([span(0, 60)], [span(0, 10), span(50, 60)]) == [span(10, 50)]


def test_subtract_can_remove_everything():
    assert subtract([span(10, 20)], [span(0, 100)]) == []


def test_subtract_with_no_overlap_changes_nothing():
    assert subtract([span(0, 10)], [span(20, 30)]) == [span(0, 10)]


def test_subtract_of_several_cuts_from_several_spans():
    result = subtract([span(0, 30), span(40, 70)], [span(10, 15), span(25, 45), span(60, 65)])

    assert result == [span(0, 10), span(15, 25), span(45, 60), span(65, 70)]


def test_subtract_nothing_leaves_the_span_alone():
    assert subtract([span(0, 10)], []) == [span(0, 10)]


def test_total_seconds_counts_overlaps_once():
    # 0-10 and 5-15 cover 15 minutes, not 20.
    assert total_seconds([span(0, 10), span(5, 15)]) == 15 * 60


def test_total_seconds_of_nothing_is_zero():
    assert total_seconds([]) == 0


def test_total_seconds_rounds_to_whole_seconds():
    start = BASE
    assert total_seconds([(start, start + timedelta(seconds=90, milliseconds=400))]) == 90
    assert total_seconds([(start, start + timedelta(seconds=90, milliseconds=600))]) == 91
