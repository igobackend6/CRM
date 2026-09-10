import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/rechurn/domain/entities/rechurn_list_state.dart';
import 'package:mobile/features/rechurn/presentation/providers/rechurn_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'fake_rechurn_repository.dart';
import 'rechurn_test_container.dart';

void main() {
  group('RechurnListController realtime (Phase 21B)', () {
    test('a lead or allocation event debounces a refresh of the queue', () async {
      final repo = FakeRechurnRepository()
        ..itemsToReturn = [testRechurnLeadCard(id: 'l1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildRechurnTestContainer(rechurnRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);
      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.success);

      repo
        ..itemsToReturn = [testRechurnLeadCard(id: 'l1'), testRechurnLeadCard(id: 'l2')]
        ..totalToReturn = 2;
      realtime.emitUpdate('leads', {'id': 'l1', 'workspace_id': 'w1'});

      await waitUntil(() => container.read(rechurnListControllerProvider).items.length == 2);
    });

    test('an event on an unrelated table is ignored', () async {
      final repo = FakeRechurnRepository()
        ..itemsToReturn = [testRechurnLeadCard(id: 'l1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildRechurnTestContainer(rechurnRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);
      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.success);

      repo
        ..itemsToReturn = [testRechurnLeadCard(id: 'l1'), testRechurnLeadCard(id: 'l2')]
        ..totalToReturn = 2;
      realtime.emitInsert('notifications', {'id': 'n1', 'workspace_id': 'w1'});

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(container.read(rechurnListControllerProvider).items, hasLength(1));
    });
  });
}
