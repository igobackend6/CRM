import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/activity/domain/entities/activity_range.dart';
import 'package:mobile/features/activity/domain/entities/activity_summary.dart';
import 'package:mobile/features/analytics/domain/call_analytics_period.dart';
import 'package:mobile/features/analytics/domain/format_clock.dart';

void main() {
  group('ActivitySummary.fromJson', () {
    test('reads every total and the break status', () {
      final summary = ActivitySummary.fromJson({
        'login_seconds': 254,
        'talk_seconds': 60,
        'wrap_up_seconds': 30,
        'break_seconds': 10,
        'idle_seconds': 154,
        'on_break': true,
        'break_started_at': '2026-09-24T08:30:00+00:00',
      });

      expect(summary.loginSeconds, 254);
      expect(summary.talkSeconds, 60);
      expect(summary.wrapUpSeconds, 30);
      expect(summary.breakSeconds, 10);
      expect(summary.idleSeconds, 154);
      expect(summary.status.onBreak, isTrue);
      expect(summary.status.breakStartedAt, DateTime.utc(2026, 9, 24, 8, 30));
    });

    test('missing fields fall back to zero / not on break', () {
      final summary = ActivitySummary.fromJson(const {});

      expect(summary.loginSeconds, 0);
      expect(summary.talkSeconds, 0);
      expect(summary.wrapUpSeconds, 0);
      expect(summary.breakSeconds, 0);
      expect(summary.idleSeconds, 0);
      expect(summary.status.onBreak, isFalse);
      expect(summary.status.breakStartedAt, isNull);
    });
  });

  group('ActivityStatus.fromJson', () {
    test('a null break_started_at stays null', () {
      final status = ActivityStatus.fromJson(const {'on_break': false, 'break_started_at': null});

      expect(status.onBreak, isFalse);
      expect(status.breakStartedAt, isNull);
    });
  });

  group('ActivityRange.period', () {
    // Wednesday 2026-09-23.
    final now = DateTime(2026, 9, 23, 15, 40);

    test('today is the local day', () {
      final period = ActivityRange.today.period(now);

      expect(period.kind, AnalyticsPeriodKind.day);
      expect(period.start, DateTime(2026, 9, 23));
    });

    test('yesterday is the day before', () {
      final period = ActivityRange.yesterday.period(now);

      expect(period.kind, AnalyticsPeriodKind.day);
      expect(period.start, DateTime(2026, 9, 22));
    });

    test('this week starts on Monday', () {
      final period = ActivityRange.thisWeek.period(now);

      expect(period.kind, AnalyticsPeriodKind.week);
      expect(period.start, DateTime(2026, 9, 21));
    });

    test('this month starts on the 1st', () {
      final period = ActivityRange.thisMonth.period(now);

      expect(period.kind, AnalyticsPeriodKind.month);
      expect(period.start, DateTime(2026, 9));
    });

    test('labels match the dropdown', () {
      expect([for (final r in ActivityRange.values) r.label], ['Today', 'Yesterday', 'This week', 'This month']);
    });
  });

  group('formatClock', () {
    test('writes a 12-hour time with no leading zero on the hour', () {
      expect(formatClock(DateTime(2026, 9, 24, 15, 5)), '3:05 PM');
      expect(formatClock(DateTime(2026, 9, 24, 9, 30)), '9:30 AM');
    });

    test('midnight and noon are 12', () {
      expect(formatClock(DateTime(2026, 9, 24, 0, 7)), '12:07 AM');
      expect(formatClock(DateTime(2026, 9, 24, 12, 0)), '12:00 PM');
    });
  });
}
