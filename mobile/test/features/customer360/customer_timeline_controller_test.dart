import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/customer360/domain/entities/activity_filter.dart';
import 'package:mobile/features/customer360/domain/entities/timeline_list_state.dart';
import 'package:mobile/features/customer360/presentation/providers/customer360_providers.dart';

import 'customer360_test_container.dart';
import 'fake_customer_repository.dart';

void main() {
  group('CustomerTimelineController', () {
    test('refresh loads the first page', () async {
      final repo = FakeCustomerRepository()
        ..timelineItemsToReturn = [testTimelineItem(id: 'a'), testTimelineItem(id: 'b')]
        ..timelineTotalToReturn = 2;
      final container = await buildCustomerTestContainer(customerRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);

      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();

      final state = container.read(customerTimelineControllerProvider('c1'));
      expect(state.status, TimelineListStatus.success);
      expect(state.items, hasLength(2));
      expect(state.hasMore, isFalse);
    });

    test('an empty result is represented as the empty status', () async {
      final container = await buildCustomerTestContainer(customerRepository: FakeCustomerRepository());
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);

      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();

      expect(container.read(customerTimelineControllerProvider('c1')).status, TimelineListStatus.empty);
    });

    test('loadMore appends the next page and stops when exhausted', () async {
      final repo = FakeCustomerRepository()
        ..timelineItemsToReturn = [testTimelineItem(id: 'a')]
        ..timelineTotalToReturn = 2;
      final container = await buildCustomerTestContainer(customerRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);
      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();

      repo.timelineItemsToReturn = [testTimelineItem(id: 'b')];
      await container.read(customerTimelineControllerProvider('c1').notifier).loadMore();

      final state = container.read(customerTimelineControllerProvider('c1'));
      expect(state.items.map((i) => i.id), ['a', 'b']);
      expect(state.hasMore, isFalse);
    });

    test('a load error surfaces the message', () async {
      final repo = FakeCustomerRepository()..timelineError = const PermissionDeniedException('nope');
      final container = await buildCustomerTestContainer(customerRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);

      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();

      final state = container.read(customerTimelineControllerProvider('c1'));
      expect(state.status, TimelineListStatus.error);
      expect(state.errorMessage, 'nope');
    });

    test('prependItem adds a note without a refetch', () async {
      final repo = FakeCustomerRepository()
        ..timelineItemsToReturn = [testTimelineItem(id: 'a')]
        ..timelineTotalToReturn = 1;
      final container = await buildCustomerTestContainer(customerRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);
      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();

      container.read(customerTimelineControllerProvider('c1').notifier).prependItem(testTimelineItem(id: 'new', summary: 'New note'));

      final state = container.read(customerTimelineControllerProvider('c1'));
      expect(state.items.first.summary, 'New note');
      expect(state.total, 2);
    });

    // ---- Phase 15: activity filters ----

    test('setFilter narrows visibleItems and resets pagination via a fresh refresh', () async {
      final repo = FakeCustomerRepository()
        ..timelineItemsToReturn = [
          testTimelineItem(id: 'call:a', type: 'call'),
          testTimelineItem(id: 'note:b', type: 'note'),
        ]
        ..timelineTotalToReturn = 2;
      final container = await buildCustomerTestContainer(customerRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerTimelineControllerProvider('c1')).close);
      await container.read(customerTimelineControllerProvider('c1').notifier).refresh();

      await container.read(customerTimelineControllerProvider('c1').notifier).setFilter(ActivityFilter.notes);

      final state = container.read(customerTimelineControllerProvider('c1'));
      expect(state.filter, ActivityFilter.notes);
      expect(state.visibleItems.map((i) => i.id), ['note:b']);
      expect(repo.lastTimelineOffset, 0);
    });
  });
}
