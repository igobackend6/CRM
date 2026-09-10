import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/reports/domain/entities/report_date_range.dart';

void main() {
  group('ReportDateRange', () {
    test('apiValue matches the backend REPORT_DATE_RANGES values exactly', () {
      final expected = {
        ReportDateRange.today: 'today',
        ReportDateRange.yesterday: 'yesterday',
        ReportDateRange.thisWeek: 'this_week',
        ReportDateRange.lastWeek: 'last_week',
        ReportDateRange.thisMonth: 'this_month',
        ReportDateRange.lastMonth: 'last_month',
        ReportDateRange.custom: 'custom',
        ReportDateRange.allTime: 'all_time',
      };
      for (final entry in expected.entries) {
        expect(entry.key.apiValue, entry.value);
      }
    });

    test('every range has a non-empty display label', () {
      for (final range in ReportDateRange.values) {
        expect(range.label, isNotEmpty);
      }
    });
  });

  group('ReportDateFilter', () {
    test('defaults to allTime with no custom bounds', () {
      const filter = ReportDateFilter();
      expect(filter.range, ReportDateRange.allTime);
      expect(filter.customSince, isNull);
      expect(filter.customUntil, isNull);
    });

    test('copyWith replaces only the given fields', () {
      const filter = ReportDateFilter(range: ReportDateRange.thisWeek);
      final since = DateTime.utc(2026, 1, 1);
      final until = DateTime.utc(2026, 2, 1);

      final updated = filter.copyWith(range: ReportDateRange.custom, customSince: since, customUntil: until);

      expect(updated.range, ReportDateRange.custom);
      expect(updated.customSince, since);
      expect(updated.customUntil, until);
    });

    test('copyWith preserves existing fields when omitted', () {
      final since = DateTime.utc(2026, 1, 1);
      final filter = ReportDateFilter(range: ReportDateRange.custom, customSince: since, customUntil: since);

      final updated = filter.copyWith(range: ReportDateRange.today);

      expect(updated.range, ReportDateRange.today);
      expect(updated.customSince, since);
    });
  });
}
