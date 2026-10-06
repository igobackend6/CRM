import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/leads/domain/entities/bulk_action_result.dart';
import 'package:mobile/features/leads/domain/entities/lead_bulk_action.dart';
import 'package:mobile/features/leads/domain/entities/lead_filters.dart';
import 'package:mobile/features/leads/domain/entities/lead_list_state.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_lead_repository.dart';
import 'lead_test_container.dart';

void main() {
  group('LeadListController', () {
    test('loads successfully and lands in success', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1'), testLead(id: 'l2')]
        ..totalToReturn = 2;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);

      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);

      final state = container.read(leadListControllerProvider);
      expect(state.items, hasLength(2));
      expect(state.total, 2);
    });

    test('an empty result lands in empty, not error', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = []
        ..totalToReturn = 0;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);

      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.empty);
    });

    test('a repository failure lands in error with the exception message', () async {
      final leadRepo = FakeLeadRepository()..listError = const NetworkException('Could not reach the server.');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);

      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.error);

      expect(container.read(leadListControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('updateSearch debounces then refreshes with the search term', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead()]
        ..totalToReturn = 1;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);

      container.read(leadListControllerProvider.notifier).updateSearch('acme');

      await waitUntil(() => leadRepo.lastSearch == 'acme', timeout: const Duration(seconds: 2));
    });

    test('loadMore appends the next page and keeps existing items on failure', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 3;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);
      expect(container.read(leadListControllerProvider).hasMore, isTrue);

      leadRepo.leadsToReturn = [testLead(id: 'l2')];
      await container.read(leadListControllerProvider.notifier).loadMore();

      final state = container.read(leadListControllerProvider);
      expect(state.items.map((l) => l.id), containsAll(['l1', 'l2']));
      expect(leadRepo.lastOffset, 1);
    });

    // ---- Phase 13: bulk selection ----

    test('selectAllVisible selects every currently-loaded lead; clearSelection empties it', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1'), testLead(id: 'l2')]
        ..totalToReturn = 2;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);

      final notifier = container.read(leadListControllerProvider.notifier);
      notifier.enterSelectionMode();
      notifier.selectAllVisible();
      expect(container.read(leadListControllerProvider).selectedIds, {'l1', 'l2'});

      notifier.clearSelection();
      expect(container.read(leadListControllerProvider).selectedIds, isEmpty);
      expect(container.read(leadListControllerProvider).selectionMode, isTrue);
    });

    test('toggleSelection adds then removes a single lead; exitSelectionMode clears everything', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);

      final notifier = container.read(leadListControllerProvider.notifier);
      notifier.enterSelectionMode();
      notifier.toggleSelection('l1');
      expect(container.read(leadListControllerProvider).selectedIds, {'l1'});

      notifier.toggleSelection('l1');
      expect(container.read(leadListControllerProvider).selectedIds, isEmpty);

      notifier.toggleSelection('l1');
      notifier.exitSelectionMode();
      final state = container.read(leadListControllerProvider);
      expect(state.selectionMode, isFalse);
      expect(state.selectedIds, isEmpty);
    });

    test('runBulkAction sends the selected ids and action, exits selection mode, and refreshes on success', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1'), testLead(id: 'l2')]
        ..totalToReturn = 2
        ..bulkActionResultToReturn = const BulkActionResult(total: 2, succeeded: 2, failed: 0, items: []);
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);

      final notifier = container.read(leadListControllerProvider.notifier);
      notifier.enterSelectionMode();
      notifier.selectAllVisible();

      final result = await notifier.runBulkAction(action: LeadBulkAction.changeStatus, statusId: 's2');

      expect(result?.succeeded, 2);
      expect(leadRepo.lastBulkLeadIds?.toSet(), {'l1', 'l2'});
      expect(leadRepo.lastBulkAction, LeadBulkAction.changeStatus);
      expect(leadRepo.lastBulkStatusId, 's2');
      final state = container.read(leadListControllerProvider);
      expect(state.selectionMode, isFalse);
      expect(state.selectedIds, isEmpty);
    });

    test('runBulkAction surfaces a failure message and returns null without exiting selection mode', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1
        ..bulkActionError = const ValidationException('Selected member is not an active member of this workspace.');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);

      final notifier = container.read(leadListControllerProvider.notifier);
      notifier.enterSelectionMode();
      notifier.toggleSelection('l1');

      final result = await notifier.runBulkAction(action: LeadBulkAction.assign, memberId: 'bad-member');

      expect(result, isNull);
      final state = container.read(leadListControllerProvider);
      expect(state.errorMessage, 'Selected member is not an active member of this workspace.');
      expect(state.selectionMode, isTrue);
      expect(state.selectedIds, {'l1'});
    });

    test('runBulkAction with no selection is a no-op', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);

      final result = await container.read(leadListControllerProvider.notifier).runBulkAction(action: LeadBulkAction.unassign);

      expect(result, isNull);
      expect(leadRepo.lastBulkAction, isNull);
    });

    // ---- Phase 14: advanced filters ----

    test('applyFilters stores the filter set, reruns from the first page, and sends it to the repository', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);

      const filters = LeadFilters(statusId: 's1', priority: 'high', isCustomer: true, tagId: 't1');
      await container.read(leadListControllerProvider.notifier).applyFilters(filters);

      final state = container.read(leadListControllerProvider);
      expect(state.filters, filters);
      expect(leadRepo.lastStatusId, 's1');
      expect(leadRepo.lastPriority, 'high');
      expect(leadRepo.lastIsCustomer, isTrue);
      expect(leadRepo.lastTagId, 't1');
      expect(leadRepo.lastOffset, 0);
    });

    test('clearFilters resets to an empty filter set and refreshes without any filter param', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);
      await container.read(leadListControllerProvider.notifier).applyFilters(const LeadFilters(statusId: 's1'));

      await container.read(leadListControllerProvider.notifier).clearFilters();

      final state = container.read(leadListControllerProvider);
      expect(state.filters.isEmpty, isTrue);
      expect(leadRepo.lastStatusId, isNull);
    });

    test('search and an active filter are sent together on refresh', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 1;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);
      final notifier = container.read(leadListControllerProvider.notifier);

      await notifier.applyFilters(const LeadFilters(priority: 'urgent'));
      notifier.updateSearch('acme');
      await waitUntil(() => leadRepo.lastSearch == 'acme', timeout: const Duration(seconds: 2));

      expect(leadRepo.lastPriority, 'urgent');
    });

    test('loadMore preserves the active filters on the next page request', () async {
      final leadRepo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1')]
        ..totalToReturn = 3;
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadListControllerProvider).close);
      await waitUntil(() => container.read(leadListControllerProvider).status == LeadListStatus.success);
      await container.read(leadListControllerProvider.notifier).applyFilters(const LeadFilters(sourceId: 'src1'));

      leadRepo.leadsToReturn = [testLead(id: 'l2')];
      await container.read(leadListControllerProvider.notifier).loadMore();

      expect(leadRepo.lastSourceId, 'src1');
      expect(leadRepo.lastOffset, 1);
    });
  });
}
