import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/dashboard/domain/entities/activity_list_state.dart';
import 'package:mobile/features/dashboard/presentation/providers/dashboard_providers.dart';

import '../../helpers/wait_until.dart';
import 'dashboard_test_container.dart';
import 'fake_dashboard_repository.dart';

void main() {
  group('ActivityListController', () {
    test('loads recent activity on workspace selection', () async {
      final repo = FakeDashboardRepository()
        ..activityItemsToReturn = [testActivityItem(id: 'call:call-1')]
        ..activityTotalToReturn = 1;
      final container = await buildDashboardTestContainer(dashboardRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, activityListControllerProvider).close);

      await waitUntil(() => container.read(activityListControllerProvider).status == ActivityListStatus.success);

      expect(container.read(activityListControllerProvider).items.map((i) => i.id), ['call:call-1']);
    });

    test('an empty result lands in the empty state', () async {
      final repo = FakeDashboardRepository();
      final container = await buildDashboardTestContainer(dashboardRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, activityListControllerProvider).close);

      await waitUntil(() => container.read(activityListControllerProvider).status == ActivityListStatus.empty);
    });

    test('a failure lands in the error state with its message', () async {
      final repo = FakeDashboardRepository()..activityError = const NetworkException('Could not reach the server.');
      final container = await buildDashboardTestContainer(dashboardRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, activityListControllerProvider).close);

      await waitUntil(() => container.read(activityListControllerProvider).status == ActivityListStatus.error);
      expect(container.read(activityListControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('loadMore appends the next page', () async {
      final repo = FakeDashboardRepository()
        ..activityItemsToReturn = [testActivityItem(id: 'call:call-1')]
        ..activityTotalToReturn = 2;
      final container = await buildDashboardTestContainer(dashboardRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, activityListControllerProvider).close);
      await waitUntil(() => container.read(activityListControllerProvider).status == ActivityListStatus.success);

      repo.activityItemsToReturn = [testActivityItem(id: 'call:call-2')];
      await container.read(activityListControllerProvider.notifier).loadMore();

      expect(repo.lastOffset, 1);
      expect(container.read(activityListControllerProvider).items.map((i) => i.id), ['call:call-1', 'call:call-2']);
    });

    test('refresh resets to the first page', () async {
      final repo = FakeDashboardRepository()
        ..activityItemsToReturn = [testActivityItem(id: 'call:call-1')]
        ..activityTotalToReturn = 1;
      final container = await buildDashboardTestContainer(dashboardRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, activityListControllerProvider).close);
      await waitUntil(() => container.read(activityListControllerProvider).status == ActivityListStatus.success);

      repo.activityItemsToReturn = [testActivityItem(id: 'notification:n-1', type: 'notification')];
      await container.read(activityListControllerProvider.notifier).refresh();

      expect(container.read(activityListControllerProvider).items.map((i) => i.id), ['notification:n-1']);
    });
  });
}
