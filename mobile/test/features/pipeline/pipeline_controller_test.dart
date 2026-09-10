import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/pipeline/domain/entities/pipeline_state.dart';
import 'package:mobile/features/pipeline/presentation/providers/pipeline_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_pipeline_repository.dart';
import 'pipeline_test_container.dart';

void main() {
  group('PipelineController', () {
    test('loads and groups columns on workspace selection', () async {
      final repo = FakePipelineRepository()
        ..columnsToReturn = [
          testPipelineColumn(status: testLeadStatus(id: 's1', name: 'New'), leads: [testPipelineLeadCard(id: 'lead-1')]),
        ];
      final container = await buildPipelineTestContainer(pipelineRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);

      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.success);

      final state = container.read(pipelineControllerProvider);
      expect(state.columns, hasLength(1));
      expect(state.columns.first.status.name, 'New');
      expect(state.columns.first.leads.first.id, 'lead-1');
    });

    test('columns with no leads at all land in the empty state', () async {
      final repo = FakePipelineRepository()..columnsToReturn = [testPipelineColumn(leads: const [])];
      final container = await buildPipelineTestContainer(pipelineRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);

      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.empty);
    });

    test('no configured statuses also lands in the empty state', () async {
      final repo = FakePipelineRepository()..columnsToReturn = [];
      final container = await buildPipelineTestContainer(pipelineRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);

      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.empty);
    });

    test('a failure lands in the error state with its message', () async {
      final repo = FakePipelineRepository()..getPipelineError = const NetworkException('Could not reach the server.');
      final container = await buildPipelineTestContainer(pipelineRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);

      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.error);
      expect(container.read(pipelineControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('updateSearch debounces then refreshes with the new query', () async {
      final repo = FakePipelineRepository()..columnsToReturn = [testPipelineColumn(leads: [testPipelineLeadCard()])];
      final container = await buildPipelineTestContainer(pipelineRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);
      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.success);

      container.read(pipelineControllerProvider.notifier).updateSearch('acme');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(repo.lastSearch, 'acme');
    });

    test('changeStatus calls the repository and refreshes on success', () async {
      final repo = FakePipelineRepository()..columnsToReturn = [testPipelineColumn(leads: [testPipelineLeadCard()])];
      final container = await buildPipelineTestContainer(pipelineRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);
      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.success);

      final ok = await container.read(pipelineControllerProvider.notifier).changeStatus(leadId: 'lead-1', statusId: 's2');

      expect(ok, true);
      expect(repo.lastLeadId, 'lead-1');
      expect(repo.lastStatusId, 's2');
      expect(repo.changeStatusCallCount, 1);
    });

    test('changeStatus surfaces a failure message and returns false without a duplicate write', () async {
      final repo = FakePipelineRepository()
        ..columnsToReturn = [testPipelineColumn(leads: [testPipelineLeadCard()])]
        ..changeStatusError = const ValidationException('Selected status does not belong to this workspace.');
      final container = await buildPipelineTestContainer(pipelineRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);
      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.success);

      final ok = await container.read(pipelineControllerProvider.notifier).changeStatus(leadId: 'lead-1', statusId: 's2');

      expect(ok, false);
      expect(container.read(pipelineControllerProvider).errorMessage, 'Selected status does not belong to this workspace.');
      expect(repo.changeStatusCallCount, 1);
    });
  });
}
