import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'fake_lead_repository.dart';
import 'lead_test_container.dart';

void main() {
  group('LeadDetailController realtime (Phase 21B)', () {
    test('an update to this exact lead elsewhere reloads it', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Acme Corp');
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).lead != null);

      leadRepo.leadToReturn = testLead(id: 'l1', name: 'Acme Corp (renamed)');
      realtime.emitUpdate('leads', {'id': 'l1', 'workspace_id': 'w1'});

      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).lead?.name == 'Acme Corp (renamed)');
    });

    test('an update to a different lead is ignored', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Acme Corp');
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).lead != null);

      leadRepo.leadToReturn = testLead(id: 'l1', name: 'Should not apply');
      realtime.emitUpdate('leads', {'id': 'l2', 'workspace_id': 'w1'});

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(container.read(leadDetailControllerProvider('l1')).lead?.name, 'Acme Corp');
    });

    test('an allocation event for this lead also reloads it', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Acme Corp');
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).lead != null);

      leadRepo.leadToReturn = testLead(id: 'l1', name: 'Reassigned Lead');
      realtime.emitInsert('allocations', {'id': 'alloc-1', 'workspace_id': 'w1', 'lead_id': 'l1'});

      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).lead?.name == 'Reassigned Lead');
    });

    test('a resync (reconnect) signal reloads the lead', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Acme Corp');
      final realtime = FakeRealtimeService();
      final container = await buildLeadTestContainer(leadRepository: leadRepo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).lead != null);

      leadRepo.leadToReturn = testLead(id: 'l1', name: 'After Reconnect');
      realtime.emitResync();

      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).lead?.name == 'After Reconnect');
    });
  });
}
