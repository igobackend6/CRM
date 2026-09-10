import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/customer360/domain/entities/timeline_list_state.dart';
import 'package:mobile/features/customer360/presentation/providers/customer360_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'customer360_test_container.dart';
import 'fake_customer_repository.dart';

void main() {
  group('CustomerTimelineController realtime (Phase 21B)', () {
    test('a leads event for this customer (a converted lead) refreshes the timeline', () async {
      final repo = FakeCustomerRepository()
        ..timelineItemsToReturn = [testTimelineItem(id: 'note:n1')]
        ..timelineTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildCustomerTestContainer(customerRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);
      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();
      await waitUntil(() => container.read(customerTimelineControllerProvider('c1')).status == TimelineListStatus.success);

      repo
        ..timelineItemsToReturn = [testTimelineItem(id: 'note:n1'), testTimelineItem(id: 'note:n2')]
        ..timelineTotalToReturn = 2;
      realtime.emitUpdate('leads', {'id': 'c1', 'workspace_id': 'w1'});

      await waitUntil(() => container.read(customerTimelineControllerProvider('c1')).items.length == 2);
    });

    test('a follow_ups event referencing this customer\'s lead_id refreshes the timeline', () async {
      final repo = FakeCustomerRepository()
        ..timelineItemsToReturn = [testTimelineItem(id: 'note:n1')]
        ..timelineTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildCustomerTestContainer(customerRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);
      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();
      await waitUntil(() => container.read(customerTimelineControllerProvider('c1')).status == TimelineListStatus.success);

      repo
        ..timelineItemsToReturn = [testTimelineItem(id: 'note:n1'), testTimelineItem(id: 'fu:f1')]
        ..timelineTotalToReturn = 2;
      realtime.emitInsert('follow_ups', {'id': 'f1', 'workspace_id': 'w1', 'lead_id': 'c1'});

      await waitUntil(() => container.read(customerTimelineControllerProvider('c1')).items.length == 2);
    });

    test('an event for a different lead is ignored', () async {
      final repo = FakeCustomerRepository()
        ..timelineItemsToReturn = [testTimelineItem(id: 'note:n1')]
        ..timelineTotalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildCustomerTestContainer(customerRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);
      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();
      await waitUntil(() => container.read(customerTimelineControllerProvider('c1')).status == TimelineListStatus.success);

      repo.timelineItemsToReturn = [testTimelineItem(id: 'note:n1'), testTimelineItem(id: 'note:n2')];
      realtime.emitUpdate('leads', {'id': 'some-other-lead', 'workspace_id': 'w1'});

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(container.read(customerTimelineControllerProvider('c1')).items, hasLength(1));
    });
  });
}
