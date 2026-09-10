import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/rechurn/domain/entities/rechurn_filters.dart';
import 'package:mobile/features/rechurn/domain/entities/rechurn_list_state.dart';
import 'package:mobile/features/rechurn/presentation/providers/rechurn_providers.dart';

import '../../helpers/wait_until.dart';
import '../pipeline/fake_pipeline_repository.dart';
import 'fake_rechurn_repository.dart';
import 'rechurn_test_container.dart';

void main() {
  group('RechurnListController', () {
    test('loads the queue on workspace selection', () async {
      final repo = FakeRechurnRepository()
        ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1', name: 'Acme Corp')]
        ..totalToReturn = 1;
      final container = await buildRechurnTestContainer(rechurnRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);

      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.success);

      final state = container.read(rechurnListControllerProvider);
      expect(state.items, hasLength(1));
      expect(state.items.first.name, 'Acme Corp');
      expect(state.total, 1);
    });

    test('an empty queue lands in the empty state', () async {
      final repo = FakeRechurnRepository();
      final container = await buildRechurnTestContainer(rechurnRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);

      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.empty);
    });

    test('a failure lands in the error state with its message', () async {
      final repo = FakeRechurnRepository()..getQueueError = const NetworkException('Could not reach the server.');
      final container = await buildRechurnTestContainer(rechurnRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);

      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.error);
      expect(container.read(rechurnListControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('updateSearch debounces then refreshes with the new query', () async {
      final repo = FakeRechurnRepository()
        ..itemsToReturn = [testRechurnLeadCard()]
        ..totalToReturn = 1;
      final container = await buildRechurnTestContainer(rechurnRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);
      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.success);

      container.read(rechurnListControllerProvider.notifier).updateSearch('acme');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(repo.lastSearch, 'acme');
    });

    test('applyFilters forwards the segment/inactive-days to the repository and reruns from offset 0', () async {
      final repo = FakeRechurnRepository()
        ..itemsToReturn = [testRechurnLeadCard()]
        ..totalToReturn = 1;
      final container = await buildRechurnTestContainer(rechurnRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);
      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.success);

      await container
          .read(rechurnListControllerProvider.notifier)
          .applyFilters(const RechurnFilters(segment: 'lost', inactiveDays: 90));

      expect(repo.lastSegment, 'lost');
      expect(repo.lastInactiveDays, 90);
      expect(repo.lastOffset, 0);
      expect(container.read(rechurnListControllerProvider).filters.segment, 'lost');
    });

    test('loadMore appends the next page and stops once everything is loaded', () async {
      final repo = FakeRechurnRepository()
        ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1')]
        ..totalToReturn = 2;
      final container = await buildRechurnTestContainer(rechurnRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);
      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.success);
      expect(container.read(rechurnListControllerProvider).hasMore, isTrue);

      repo.itemsToReturn = [testRechurnLeadCard(id: 'lead-2')];
      await container.read(rechurnListControllerProvider.notifier).loadMore();

      final state = container.read(rechurnListControllerProvider);
      expect(state.items.map((i) => i.id), ['lead-1', 'lead-2']);
      expect(state.hasMore, isFalse);
    });

    test('changeStatus reuses PipelineRepository and refreshes the queue on success', () async {
      final repo = FakeRechurnRepository()
        ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1')]
        ..totalToReturn = 1;
      final pipelineRepo = FakePipelineRepository();
      final container = await buildRechurnTestContainer(rechurnRepository: repo, pipelineRepository: pipelineRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);
      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.success);

      final ok = await container.read(rechurnListControllerProvider.notifier).changeStatus(leadId: 'lead-1', statusId: 's2');

      expect(ok, isTrue);
      expect(pipelineRepo.lastLeadId, 'lead-1');
      expect(pipelineRepo.lastStatusId, 's2');
      expect(pipelineRepo.changeStatusCallCount, 1);
    });

    test('changeStatus surfaces a failure message and returns false', () async {
      final repo = FakeRechurnRepository()
        ..itemsToReturn = [testRechurnLeadCard(id: 'lead-1')]
        ..totalToReturn = 1;
      final pipelineRepo = FakePipelineRepository()..changeStatusError = const ValidationException('Selected status does not belong to this workspace.');
      final container = await buildRechurnTestContainer(rechurnRepository: repo, pipelineRepository: pipelineRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, rechurnListControllerProvider).close);
      await waitUntil(() => container.read(rechurnListControllerProvider).status == RechurnListStatus.success);

      final ok = await container.read(rechurnListControllerProvider.notifier).changeStatus(leadId: 'lead-1', statusId: 's2');

      expect(ok, isFalse);
      expect(container.read(rechurnListControllerProvider).errorMessage, 'Selected status does not belong to this workspace.');
    });
  });
}
