import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leads/domain/entities/lead_list_state.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'fake_lead_repository.dart';
import 'lead_test_container.dart';

void main() {
  group('LeadListController realtime (Phase 21B)', () {
    test('a lead insert/update elsewhere debounces a refresh that picks up the new data', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);
      expect(container.read(leadListControllerProvider).items, hasLength(1));

      // The repository now has an extra lead, as if it were created by
      // another user — the realtime event is just the trigger to notice.
      leadRepo
        ..leadsToReturn = [testLead(id: 'l1'), testLead(id: 'l2')]
        ..totalToReturn = 2;
      realtime.emitInsert('leads', {'id': 'l2', 'workspace_id': 'w1'});

      await waitUntil(() => container.read(leadListControllerProvider).items.length == 2);
    });

    test('a lead delete removes the row immediately, without waiting on a refresh', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1'), testLead(id: 'l2')]
        ..totalToReturn = 2;
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).items.length == 2);

      realtime.emitDelete('leads', {'id': 'l1'});

      await waitUntil(() => container.read(leadListControllerProvider).items.length == 1);
      final state = container.read(leadListControllerProvider);
      expect(state.items.single.id, 'l2');
      expect(state.total, 1);
    });

    test('a delete for an id not currently loaded is a safe no-op', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).items.length == 1);

      realtime.emitDelete('leads', {'id': 'does-not-exist'});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(leadListControllerProvider).items, hasLength(1));
    });

    test('an allocation change also debounces a refresh', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).items.length == 1);

      leadRepo
        ..leadsToReturn = [testLead(id: 'l1'), testLead(id: 'l2')]
        ..totalToReturn = 2;
      realtime.emitInsert('allocations', {'id': 'alloc-1', 'workspace_id': 'w1', 'assigned_member_id': 'm2'});

      await waitUntil(() => container.read(leadListControllerProvider).items.length == 2);
    });

    test('a burst of events coalesces into one refresh (no crash, ends up consistent)', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).items.length == 1);

      leadRepo
        ..leadsToReturn = [testLead(id: 'l1'), testLead(id: 'l2'), testLead(id: 'l3')]
        ..totalToReturn = 3;
      for (var i = 0; i < 5; i++) {
        realtime.emitUpdate('leads', {'id': 'l1', 'workspace_id': 'w1'});
      }

      await waitUntil(() => container.read(leadListControllerProvider).items.length == 3);
    });

    test('an event on an unrelated table is ignored', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).items.length == 1);

      leadRepo
        ..leadsToReturn = [testLead(id: 'l1'), testLead(id: 'l2')]
        ..totalToReturn = 2;
      realtime.emitInsert('notifications', {'id': 'n1', 'workspace_id': 'w1'});

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(container.read(leadListControllerProvider).items, hasLength(1));
    });
  });
}
