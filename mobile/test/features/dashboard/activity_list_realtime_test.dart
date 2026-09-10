import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/dashboard/domain/entities/activity_list_state.dart';
import 'package:mobile/features/dashboard/presentation/providers/dashboard_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'dashboard_test_container.dart';
import 'fake_dashboard_repository.dart';

void main() {
  group('ActivityListController realtime (Phase 21B)', () {
    test('any relevant table event debounces a refresh and invalidates the KPI summary', () async {
      final repo = FakeDashboardRepository()
        ..activityItemsToReturn = [testActivityItem(id: 'call:c1')]
        ..activityTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildDashboardTestContainer(dashboardRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, activityListControllerProvider).close);
      await waitUntil(() => container.read(activityListControllerProvider).status == ActivityListStatus.success);
      await container.read(dashboardSummaryProvider.future); // let the initial summary resolve

      repo
        ..activityItemsToReturn = [testActivityItem(id: 'call:c1'), testActivityItem(id: 'lead:l1')]
        ..activityTotalToReturn = 2
        ..summaryToReturn = testSummary(totalActiveLeads: 42);
      realtime.emitInsert('leads', {'id': 'l1', 'workspace_id': 'w1'});

      await waitUntil(() => container.read(activityListControllerProvider).items.length == 2, timeout: const Duration(seconds: 3));
      final summary = await container.read(dashboardSummaryProvider.future);
      expect(summary.totalActiveLeads, 42);
    });

    test('a burst of events across several tables coalesces into one refresh', () async {
      final repo = FakeDashboardRepository()
        ..activityItemsToReturn = [testActivityItem(id: 'call:c1')]
        ..activityTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildDashboardTestContainer(dashboardRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, activityListControllerProvider).close);
      await waitUntil(() => container.read(activityListControllerProvider).status == ActivityListStatus.success);

      repo
        ..activityItemsToReturn = [testActivityItem(id: 'call:c1'), testActivityItem(id: 'lead:l1'), testActivityItem(id: 'follow_up:f1')]
        ..activityTotalToReturn = 3;
      realtime
        ..emitInsert('leads', {'id': 'l1', 'workspace_id': 'w1'})
        ..emitInsert('follow_ups', {'id': 'f1', 'workspace_id': 'w1'})
        ..emitInsert('notifications', {'id': 'n1', 'workspace_id': 'w1'});

      await waitUntil(() => container.read(activityListControllerProvider).items.length == 3, timeout: const Duration(seconds: 3));
    });
  });
}
