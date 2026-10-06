from datetime import datetime

# A half-open span of time [start, end). All datetimes must be timezone-aware
# (mixing naive and aware would raise); the services always pass UTC.
Interval = tuple[datetime, datetime]


def merge(intervals: list[Interval]) -> list[Interval]:
    """Sorted, non-overlapping, non-adjacent spans covering exactly the same
    time as [intervals]. Empty and inverted spans (end <= start) are dropped,
    so callers can pass raw rows without pre-filtering."""
    spans = sorted((s, e) for s, e in intervals if e > s)
    merged: list[Interval] = []
    for start, end in spans:
        if merged and start <= merged[-1][1]:
            if end > merged[-1][1]:
                merged[-1] = (merged[-1][0], end)
        else:
            merged.append((start, end))
    return merged


def clip(intervals: list[Interval], lo: datetime, hi: datetime) -> list[Interval]:
    """[intervals] restricted to the window [lo, hi)."""
    if hi <= lo:
        return []
    return merge([(max(s, lo), min(e, hi)) for s, e in intervals])


def intersect(a: list[Interval], b: list[Interval]) -> list[Interval]:
    """The time covered by both [a] and [b]."""
    left, right = merge(a), merge(b)
    result: list[Interval] = []
    i = j = 0
    while i < len(left) and j < len(right):
        start = max(left[i][0], right[j][0])
        end = min(left[i][1], right[j][1])
        if end > start:
            result.append((start, end))
        # Advance whichever span finishes first.
        if left[i][1] < right[j][1]:
            i += 1
        else:
            j += 1
    return result


def subtract(a: list[Interval], b: list[Interval]) -> list[Interval]:
    """The time covered by [a] but not by [b]."""
    remaining = merge(a)
    for cut_start, cut_end in merge(b):
        pieces: list[Interval] = []
        for start, end in remaining:
            if cut_end <= start or cut_start >= end:
                pieces.append((start, end))
                continue
            if cut_start > start:
                pieces.append((start, cut_start))
            if cut_end < end:
                pieces.append((cut_end, end))
        remaining = pieces
    return remaining


def total_seconds(intervals: list[Interval]) -> int:
    """Whole seconds covered (overlaps counted once)."""
    return int(round(sum((e - s).total_seconds() for s, e in merge(intervals))))
