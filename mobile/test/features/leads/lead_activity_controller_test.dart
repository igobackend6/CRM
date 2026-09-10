import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/customer360/domain/entities/activity_filter.dart';
import 'package:mobile/features/customer360/domain/entities/timeline_list_state.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';

import 'fake_lead_repository.dart';
import 'lead_test_container.dart';

void main() {
  group('LeadActivityController', () {
    test('refresh loads the first page', () async {
      final repo = FakeLeadRepository()
        ..activityItemsToReturn = [testTimelineItem(id: 'call:a'), testTimelineItem(id: 'note:b')]
        ..activityTotalToReturn = 2;
      final container = await buildLeadTestContainer(leadRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadActivityControllerProvider('l1')).close);

      await container.read(leadActivityControllerProvider('l1').notifier).refresh();

      final state = container.read(leadActivityControllerProvider('l1'));
      expect(state.status, TimelineListStatus.success);
      expect(state.items, hasLength(2));
      expect(state.hasMore, isFalse);
    });

    test('an empty result is represented as the empty status', () async {
      final container = await buildLeadTestContainer(leadRepository: FakeLeadRepository());
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadActivityControllerProvider('l1')).close);

      await container.read(leadActivityControllerProvider('l1').notifier).refresh();

      expect(container.read(leadActivityControllerProvider('l1')).status, TimelineListStatus.empty);
    });

    test('loadMore appends the next page and stops when exhausted', () async {
      final repo = FakeLeadRepository()
        ..activityItemsToReturn = [testTimelineItem(id: 'call:a')]
        ..activityTotalToReturn = 2;
      final container = await buildLeadTestContainer(leadRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadActivityControllerProvider('l1')).close);
      await container.read(leadActivityControllerProvider('l1').notifier).refresh();

      repo.activityItemsToReturn = [testTimelineItem(id: 'call:b')];
      await container.read(leadActivityControllerProvider('l1').notifier).loadMore();

      final state = container.read(leadActivityControllerProvider('l1'));
      expect(state.items.map((i) => i.id), ['call:a', 'call:b']);
      expect(state.hasMore, isFalse);
    });

    test('a load error surfaces the message', () async {
      final repo = FakeLeadRepository()..activityError = const PermissionDeniedException('nope');
      final container = await buildLeadTestContainer(leadRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadActivityControllerProvider('l1')).close);

      await container.read(leadActivityControllerProvider('l1').notifier).refresh();

      final state = container.read(leadActivityControllerProvider('l1'));
      expect(state.status, TimelineListStatus.error);
      expect(state.errorMessage, 'nope');
    });

    test('prependItem adds a note without a refetch', () async {
      final repo = FakeLeadRepository()
        ..activityItemsToReturn = [testTimelineItem(id: 'call:a')]
        ..activityTotalToReturn = 1;
      final container = await buildLeadTestContainer(leadRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadActivityControllerProvider('l1')).close);
      await container.read(leadActivityControllerProvider('l1').notifier).refresh();

      container.read(leadActivityControllerProvider('l1').notifier).prependItem(testTimelineItem(id: 'note:new', summary: 'New note'));

      final state = container.read(leadActivityControllerProvider('l1'));
      expect(state.items.first.summary, 'New note');
      expect(state.total, 2);
    });

    // ---- Phase 15: activity filters ----

    test('setFilter narrows visibleItems and resets pagination via a fresh refresh', () async {
      final repo = FakeLeadRepository()
        ..activityItemsToReturn = [
          testTimelineItem(id: 'call:a', type: 'call'),
          testTimelineItem(id: 'note:b', type: 'note'),
        ]
        ..activityTotalToReturn = 2;
      final container = await buildLeadTestContainer(leadRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadActivityControllerProvider('l1')).close);
      await container.read(leadActivityControllerProvider('l1').notifier).refresh();

      await container.read(leadActivityControllerProvider('l1').notifier).setFilter(ActivityFilter.calls);

      final state = container.read(leadActivityControllerProvider('l1'));
      expect(state.filter, ActivityFilter.calls);
      expect(state.visibleItems.map((i) => i.id), ['call:a']);
      // The unfiltered items/total are still the full server page — the
      // filter is a display-only narrowing.
      expect(state.items, hasLength(2));
      expect(repo.lastActivityOffset, 0);
    });
  });
}
