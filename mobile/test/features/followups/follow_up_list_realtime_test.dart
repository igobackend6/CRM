import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/followups/domain/entities/follow_up_list_state.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'fake_follow_up_repository.dart';
import 'followup_test_container.dart';

void main() {
  group('FollowUpListController realtime (Phase 21B)', () {
    test('a follow-up created/updated elsewhere debounces a refresh', () async {
      final repo = FakeFollowUpRepository()
        ..itemsToReturn = [testFollowUp(id: 'f1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildFollowUpTestContainer(followUpRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpListControllerProvider).close);
      await waitUntil(() => container.read(followUpListControllerProvider).status == FollowUpListStatus.success);

      repo
        ..itemsToReturn = [testFollowUp(id: 'f1'), testFollowUp(id: 'f2')]
        ..totalToReturn = 2;
      realtime.emitInsert('follow_ups', {'id': 'f2', 'workspace_id': 'w1'});

      await waitUntil(() => container.read(followUpListControllerProvider).items.length == 2);
    });

    test('an event on an unrelated table is ignored', () async {
      final repo = FakeFollowUpRepository()
        ..itemsToReturn = [testFollowUp(id: 'f1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildFollowUpTestContainer(followUpRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpListControllerProvider).close);
      await waitUntil(() => container.read(followUpListControllerProvider).items.length == 1);

      repo
        ..itemsToReturn = [testFollowUp(id: 'f1'), testFollowUp(id: 'f2')]
        ..totalToReturn = 2;
      realtime.emitInsert('leads', {'id': 'l1', 'workspace_id': 'w1'});

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(container.read(followUpListControllerProvider).items, hasLength(1));
    });
  });
}
