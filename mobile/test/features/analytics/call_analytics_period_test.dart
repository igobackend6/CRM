import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/domain/call_analytics_period.dart';
import 'package:mobile/features/reports/domain/entities/call_trends.dart';

// Wednesday 23 Sep 2026, 15:30 local.
final _now = DateTime(2026, 9, 23, 15, 30);

void main() {
  group('day', () {
    test('opens at local midnight and closes at the next local midnight', () {
      final period = CallAnalyticsPeriod.day(_now);

      expect(period.start, DateTime(2026, 9, 23));
      expect(period.end, DateTime(2026, 9, 24));
      expect(period.since, DateTime(2026, 9, 23).toUtc());
      expect(period.until, DateTime(2026, 9, 24).toUtc());
    });

    test('is charted per hour', () {
      expect(CallAnalyticsPeriod.day(_now).granularity, CallTrendGranularity.hour);
    });

    test('rolls over a month boundary', () {
      expect(CallAnalyticsPeriod.day(DateTime(2026, 9, 30)).end, DateTime(2026, 10, 1));
    });
  });

  group('week', () {
    test('starts on the Monday of the containing week', () {
      final period = CallAnalyticsPeriod.week(_now); // a Wednesday

      expect(period.start, DateTime(2026, 9, 21));
      expect(period.end, DateTime(2026, 9, 28));
    });

    test('a Sunday belongs to the week that started six days earlier', () {
      expect(CallAnalyticsPeriod.week(DateTime(2026, 9, 27)).start, DateTime(2026, 9, 21));
    });

    test('a Monday starts its own week', () {
      expect(CallAnalyticsPeriod.week(DateTime(2026, 9, 21)).start, DateTime(2026, 9, 21));
    });

    test('a week that straddles a month start still begins on a Monday', () {
      expect(CallAnalyticsPeriod.week(DateTime(2026, 10, 1)).start, DateTime(2026, 9, 28));
    });

    test('is charted per day', () {
      expect(CallAnalyticsPeriod.week(_now).granularity, CallTrendGranularity.day);
    });
  });

  group('month', () {
    test('spans the first of the month to the first of the next', () {
      final period = CallAnalyticsPeriod.month(_now);

      expect(period.start, DateTime(2026, 9));
      expect(period.end, DateTime(2026, 10));
    });

    test('December closes at January of the next year', () {
      expect(CallAnalyticsPeriod.month(DateTime(2026, 12, 15)).end, DateTime(2027, 1));
    });
  });

  group('isCurrent', () {
    test('is true for the period containing now and false for its neighbours', () {
      final today = CallAnalyticsPeriod.day(_now);

      expect(today.isCurrent(_now), isTrue);
      expect(today.shifted(-1).isCurrent(_now), isFalse);
      expect(today.shifted(1).isCurrent(_now), isFalse);
    });

    test('a period is half-open: its end instant belongs to the next one', () {
      final today = CallAnalyticsPeriod.day(_now);

      expect(today.isCurrent(DateTime(2026, 9, 23)), isTrue);
      expect(today.isCurrent(DateTime(2026, 9, 24)), isFalse);
    });
  });

  group('shifted', () {
    test('moves by whole periods of the same kind', () {
      expect(CallAnalyticsPeriod.day(_now).shifted(-3).start, DateTime(2026, 9, 20));
      expect(CallAnalyticsPeriod.week(_now).shifted(-1).start, DateTime(2026, 9, 14));
      expect(CallAnalyticsPeriod.month(_now).shifted(-1).start, DateTime(2026, 8));
      expect(CallAnalyticsPeriod.month(DateTime(2026, 1, 10)).shifted(-1).start, DateTime(2025, 12));
    });
  });

  group('label', () {
    test('uses friendly names for the current and previous day', () {
      final today = CallAnalyticsPeriod.day(_now);

      expect(today.label(_now), 'Today');
      expect(today.shifted(-1).label(_now), 'Yesterday');
    });

    test('uses the date for older days, adding the year only when it differs', () {
      expect(CallAnalyticsPeriod.day(DateTime(2026, 9, 10)).label(_now), '10 Sep');
      expect(CallAnalyticsPeriod.day(DateTime(2025, 9, 10)).label(_now), '10 Sep 2025');
    });

    test('names the current week and month, the range otherwise', () {
      expect(CallAnalyticsPeriod.week(_now).label(_now), 'This week');
      expect(CallAnalyticsPeriod.week(_now).shifted(-1).label(_now), '14 Sep – 20 Sep');
      expect(CallAnalyticsPeriod.month(_now).label(_now), 'This month');
      expect(CallAnalyticsPeriod.month(_now).shifted(-1).label(_now), 'August');
      expect(CallAnalyticsPeriod.month(DateTime(2025, 3)).label(_now), 'Mar 2025');
    });
  });

  test('periods with the same kind and start are equal', () {
    expect(CallAnalyticsPeriod.day(DateTime(2026, 9, 23, 8)), CallAnalyticsPeriod.day(DateTime(2026, 9, 23, 22)));
    expect(CallAnalyticsPeriod.day(_now), isNot(CallAnalyticsPeriod.week(_now)));
  });
}
