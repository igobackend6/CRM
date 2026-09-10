import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/reports/domain/entities/report_date_range.dart';
import 'package:mobile/features/reports/presentation/providers/reports_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_reports_repository.dart';
import 'reports_test_container.dart';

void main() {
  group('personalReportProvider', () {
    test('loads and exposes the personal report on success', () async {
      final repo = FakeReportsRepository()..personalReportToReturn = testPersonalReport(totalCalls: 42);
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);

      final report = await container.read(personalReportProvider.future);

      expect(report.calls.totalCalls, 42);
    });

    test('surfaces a repository error through the FutureProvider', () async {
      final repo = FakeReportsRepository()..personalError = const NetworkException('Could not reach the server.');
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);

      await expectLater(container.read(personalReportProvider.future), throwsA(isA<NetworkException>()));
    });

    test('changing the date-range filter re-fetches with the new range', () async {
      final repo = FakeReportsRepository();
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);
      final sub = keepAlive(container, personalReportProvider);
      addTearDown(sub.close);

      await waitUntil(() => repo.lastRange != null);
      expect(repo.lastRange, 'all_time');

      container.read(reportDateFilterProvider.notifier).state = const ReportDateFilter(range: ReportDateRange.thisMonth);

      await waitUntil(() => repo.lastRange == 'this_month');
    });
  });
}
