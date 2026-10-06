import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/domain/call_trends_csv.dart';
import 'package:mobile/features/analytics/domain/format_talk_time.dart';
import 'package:mobile/features/analytics/domain/trend_labels.dart';
import 'package:mobile/features/reports/domain/entities/call_trends.dart';

// Buckets are built from LOCAL wall-clock times converted to UTC (exactly what
// the backend echoes back), so the assertions hold in any test-machine timezone.
CallTrendBucket _bucket(DateTime local, {int calls = 0, int unique = 0, int talk = 0}) =>
    CallTrendBucket(start: local.toUtc(), calls: calls, uniqueLeads: unique, talkTimeSeconds: talk);

CallTrends _hourly() => CallTrends(
      granularity: CallTrendGranularity.hour,
      buckets: [for (var h = 0; h < 24; h++) _bucket(DateTime(2026, 9, 24, h))],
      totalCalls: 0,
      uniqueLeads: 0,
      totalTalkTimeSeconds: 0,
    );

CallTrends _daily(int days) => CallTrends(
      granularity: CallTrendGranularity.day,
      // 21 Sep 2026 is a Monday.
      buckets: [for (var d = 0; d < days; d++) _bucket(DateTime(2026, 9, 21 + d))],
      totalCalls: 0,
      uniqueLeads: 0,
      totalTalkTimeSeconds: 0,
    );

void main() {
  group('trendAxisLabels', () {
    test('hourly bars are labelled every six hours in 12-hour form', () {
      final labels = trendAxisLabels(_hourly());

      expect(labels.length, 24);
      expect([labels[0], labels[6], labels[12], labels[18]], ['12a', '6a', '12p', '6p']);
      expect(labels.where((l) => l.isNotEmpty).length, 4);
    });

    test('a week of daily bars gets a weekday label on every bar', () {
      expect(trendAxisLabels(_daily(7)), ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
    });

    test('a month of daily bars is labelled with the day number every fifth bar', () {
      final labels = trendAxisLabels(_daily(30));

      expect(labels[0], '21');
      expect(labels[1], '');
      expect(labels[5], '26');
      expect(labels.where((l) => l.isNotEmpty).length, 6);
    });
  });

  group('bucketTimeLabel', () {
    test('an hourly bar reads as its clock range', () {
      expect(bucketTimeLabel(_bucket(DateTime(2026, 9, 24, 9)), CallTrendGranularity.hour), '9:00 AM – 10:00 AM');
      expect(bucketTimeLabel(_bucket(DateTime(2026, 9, 24, 0)), CallTrendGranularity.hour), '12:00 AM – 1:00 AM');
      expect(bucketTimeLabel(_bucket(DateTime(2026, 9, 24, 12)), CallTrendGranularity.hour), '12:00 PM – 1:00 PM');
      expect(bucketTimeLabel(_bucket(DateTime(2026, 9, 24, 23)), CallTrendGranularity.hour), '11:00 PM – 12:00 AM');
    });

    test('a daily bar reads as weekday, day and month', () {
      expect(bucketTimeLabel(_bucket(DateTime(2026, 9, 21)), CallTrendGranularity.day), 'Mon 21 Sep');
    });
  });

  group('formatTalkTime', () {
    test('keeps seconds under an hour', () {
      expect(formatTalkTime(0), '0m 0s');
      expect(formatTalkTime(45), '0m 45s');
      expect(formatTalkTime(254), '4m 14s');
      expect(formatTalkTime(3599), '59m 59s');
    });

    test('switches to hours and minutes from an hour up', () {
      expect(formatTalkTime(3600), '1h 0m');
      expect(formatTalkTime(3925), '1h 5m');
    });

    test('never shows a negative duration', () {
      expect(formatTalkTime(-5), '0m 0s');
    });
  });

  group('callTrendsCsv', () {
    test('has a header and one line per bucket, in local time', () {
      final trends = CallTrends(
        granularity: CallTrendGranularity.hour,
        buckets: [
          _bucket(DateTime(2026, 9, 24, 8), calls: 3, unique: 2, talk: 190),
          _bucket(DateTime(2026, 9, 24, 9)),
        ],
        totalCalls: 3,
        uniqueLeads: 2,
        totalTalkTimeSeconds: 190,
      );

      expect(
        callTrendsCsv(trends),
        'bucket_start,calls,unique_leads,talk_time_seconds\n'
        '2026-09-24 08:00,3,2,190\n'
        '2026-09-24 09:00,0,0,0\n',
      );
    });

    test('an empty result is just the header', () {
      expect(callTrendsCsv(CallTrends.empty), 'bucket_start,calls,unique_leads,talk_time_seconds\n');
    });
  });
}
