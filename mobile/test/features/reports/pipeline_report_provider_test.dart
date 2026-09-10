import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/reports/presentation/providers/reports_providers.dart';

import 'fake_reports_repository.dart';
import 'reports_test_container.dart';

void main() {
  group('pipelineReportProvider', () {
    test('loads and exposes the pipeline report on success', () async {
      final repo = FakeReportsRepository()..pipelineReportToReturn = testPipelineReport();
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);

      final report = await container.read(pipelineReportProvider.future);

      expect(report.convertedCustomers, 3);
      expect(report.priorityDistribution, hasLength(4));
    });

    test('surfaces a repository error (e.g. a 403 for a non-manager) through the FutureProvider', () async {
      final repo = FakeReportsRepository()..pipelineError = const PermissionDeniedException('Missing permission: reports.read');
      final container = await buildReportsTestContainer(reportsRepository: repo, role: 'team_mate');
      addTearDown(container.dispose);

      await expectLater(container.read(pipelineReportProvider.future), throwsA(isA<PermissionDeniedException>()));
    });
  });
}
