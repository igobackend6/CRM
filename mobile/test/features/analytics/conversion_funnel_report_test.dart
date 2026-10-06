import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/domain/conversion_funnel_report.dart';
import 'package:mobile/features/analytics/domain/customer_funnel.dart';
import 'package:mobile/features/reports/domain/entities/report_date_range.dart';

FunnelStage _stage(String stage, String label, Map<String, int> statuses) =>
    FunnelStage(stage: stage, label: label, statuses: [for (final e in statuses.entries) FunnelStatusRow(name: e.key, count: e.value)]);

ConversionFunnelReport _report(List<FunnelStage> stages) => ConversionFunnelReport(
      scopeLabel: 'Your pipeline',
      periodLabel: 'All time',
      generatedAt: DateTime(2026, 9, 24, 13, 5),
      customers: 3,
      inPipeline: 7,
      lost: 1,
      stages: stages,
    );

void main() {
  group('tableRows', () {
    test('lists each stage total followed by its statuses, in order', () {
      final report = _report([
        _stage('start', 'Start', {'New': 4}),
        _stage('in_progress', 'In progress', {'Contacted': 3, 'Qualified': 1}),
      ]);

      final rows = report.tableRows;

      expect(rows.map((r) => '${r.stage}|${r.status}|${r.leads}'), [
        'Start|All statuses|4',
        '|New|4',
        'In progress|All statuses|4',
        '|Contacted|3',
        '|Qualified|1',
      ]);
    });

    test('marks only the stage rows as totals', () {
      final rows = _report([_stage('start', 'Start', {'New': 2, 'Fresh': 2})]).tableRows;

      expect(rows.map((r) => r.isStageTotal), [true, false, false]);
    });

    test('share is each count as a whole percent of all leads in the period', () {
      final rows = _report([
        _stage('start', 'Start', {'New': 6}),
        _stage('in_progress', 'In progress', {'Contacted': 3}),
        _stage('closed_lost', 'Lost', {'Lost': 1}),
      ]).tableRows;

      // 10 leads in total.
      expect(rows.map((r) => r.share), ['60%', '60%', '30%', '30%', '10%', '10%']);
    });

    test('share rounds to the nearest whole percent', () {
      final rows = _report([_stage('start', 'Start', {'A': 1, 'B': 2})]).tableRows; // 33.3% / 66.7%

      expect(rows.map((r) => r.share), ['100%', '33%', '67%']);
    });

    test('with no leads at all every share is 0% and nothing divides by zero', () {
      final report = _report([_stage('start', 'Start', {'New': 0})]);

      expect(report.totalLeads, 0);
      expect(report.tableRows.map((r) => r.share), ['0%', '0%']);
    });

    test('no stages means no rows', () {
      expect(_report(const []).tableRows, isEmpty);
    });
  });

  group('describeReportFilter', () {
    test('uses the chip label for a preset range', () {
      expect(describeReportFilter(const ReportDateFilter()), 'All time');
      expect(describeReportFilter(const ReportDateFilter(range: ReportDateRange.thisWeek)), 'This week');
      expect(describeReportFilter(const ReportDateFilter(range: ReportDateRange.lastMonth)), 'Last month');
    });

    test('spells out the dates of a custom range, with the last day inclusive', () {
      // The backend window is half-open: until = the day AFTER the last included day.
      final filter = ReportDateFilter(range: ReportDateRange.custom, customSince: DateTime(2026, 9, 12), customUntil: DateTime(2026, 9, 21));

      expect(describeReportFilter(filter), '12 Sep 2026 – 20 Sep 2026');
    });

    test('a custom range that rolls over a month boundary reads correctly', () {
      final filter = ReportDateFilter(range: ReportDateRange.custom, customSince: DateTime(2026, 8, 30), customUntil: DateTime(2026, 9, 2));

      expect(describeReportFilter(filter), '30 Aug 2026 – 1 Sep 2026');
    });

    test('a "custom" range with no dates falls back to its label', () {
      expect(describeReportFilter(const ReportDateFilter(range: ReportDateRange.custom)), 'Custom');
    });
  });

  group('conversionFunnelFileName', () {
    final now = DateTime(2026, 9, 4, 9);

    test('carries the range and the date, zero-padded', () {
      expect(conversionFunnelFileName(const ReportDateFilter(range: ReportDateRange.thisWeek), now), 'conversion-funnel-this-week-2026-09-04.pdf');
      expect(conversionFunnelFileName(const ReportDateFilter(), now), 'conversion-funnel-all-time-2026-09-04.pdf');
    });

    test('is a .pdf with no characters a file system dislikes', () {
      final name = conversionFunnelFileName(const ReportDateFilter(range: ReportDateRange.lastMonth), now);

      expect(name, endsWith('.pdf'));
      expect(name, matches(RegExp(r'^[a-z0-9\-]+\.pdf$')));
    });
  });
}
