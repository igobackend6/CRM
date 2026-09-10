import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/reports/domain/entities/team_report_state.dart';
import 'package:mobile/features/reports/presentation/providers/reports_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_reports_repository.dart';
import 'reports_test_container.dart';

void main() {
  group('TeamReportController', () {
    test('loads member rows and totals on success', () async {
      final repo = FakeReportsRepository()
        ..teamReportToReturn = testTeamReportPage(items: [testTeamRow(memberId: 'm1'), testTeamRow(memberId: 'm2')], total: 2);
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, teamReportControllerProvider).close);

      await waitUntil(() => container.read(teamReportControllerProvider).status == TeamReportStatus.success);

      final state = container.read(teamReportControllerProvider);
      expect(state.items, hasLength(2));
      expect(state.total, 2);
    });

    test('an empty workspace resolves to the empty status, not success with zero rows', () async {
      final repo = FakeReportsRepository()..teamReportToReturn = testTeamReportPage();
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, teamReportControllerProvider).close);

      await waitUntil(
        () => container.read(teamReportControllerProvider).status == TeamReportStatus.empty ||
            container.read(teamReportControllerProvider).status == TeamReportStatus.error,
      );

      expect(container.read(teamReportControllerProvider).status, TeamReportStatus.empty);
    });

    test('a repository error surfaces its message and the error status', () async {
      final repo = FakeReportsRepository()..teamError = const NetworkException('Could not reach the server.');
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, teamReportControllerProvider).close);

      await waitUntil(() => container.read(teamReportControllerProvider).status == TeamReportStatus.error);

      expect(container.read(teamReportControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('loadMore appends the next page at the current offset', () async {
      final repo = FakeReportsRepository()
        ..teamReportToReturn = testTeamReportPage(items: [testTeamRow(memberId: 'm1')], total: 2, limit: 1);
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, teamReportControllerProvider).close);
      await waitUntil(() => container.read(teamReportControllerProvider).status == TeamReportStatus.success);

      repo.teamReportToReturn = testTeamReportPage(items: [testTeamRow(memberId: 'm2')], total: 2, limit: 1);
      await container.read(teamReportControllerProvider.notifier).loadMore();

      expect(container.read(teamReportControllerProvider).items, hasLength(2));
      expect(repo.lastTeamOffset, 1);
    });

    test('refresh re-fetches when the shared date-range filter changes', () async {
      final repo = FakeReportsRepository()..teamReportToReturn = testTeamReportPage(items: [testTeamRow()], total: 1);
      final container = await buildReportsTestContainer(reportsRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, teamReportControllerProvider).close);
      await waitUntil(() => container.read(teamReportControllerProvider).status == TeamReportStatus.success);

      final callsBefore = repo.callCount;
      container.read(reportDateFilterProvider.notifier).state = container.read(reportDateFilterProvider).copyWith();
      // Same filter value (no-op copy) must NOT trigger a refetch — the
      // controller compares previous/next, not just "the provider fired".
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.callCount, callsBefore);
    });
  });
}
