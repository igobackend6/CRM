import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/pipeline/domain/entities/pipeline_state.dart';
import 'package:mobile/features/pipeline/presentation/providers/pipeline_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'fake_pipeline_repository.dart';
import 'pipeline_test_container.dart';

void main() {
  group('PipelineController realtime (Phase 21B)', () {
    test('a lead or allocation event debounces a full board reload', () async {
      final repo = FakePipelineRepository()..columnsToReturn = [testPipelineColumn(leads: [testPipelineLeadCard(id: 'l1')])];
      final realtime = FakeRealtimeService();
      final container = await buildPipelineTestContainer(pipelineRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);
      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.success);

      repo.columnsToReturn = [
        testPipelineColumn(leads: [testPipelineLeadCard(id: 'l1'), testPipelineLeadCard(id: 'l2')]),
      ];
      realtime.emitUpdate('leads', {'id': 'l1', 'workspace_id': 'w1'});

      await waitUntil(() => container.read(pipelineControllerProvider).columns.first.leads.length == 2);
    });

    test('an event on an unrelated table is ignored', () async {
      final repo = FakePipelineRepository()..columnsToReturn = [testPipelineColumn(leads: [testPipelineLeadCard(id: 'l1')])];
      final realtime = FakeRealtimeService();
      final container = await buildPipelineTestContainer(pipelineRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, pipelineControllerProvider).close);
      await waitUntil(() => container.read(pipelineControllerProvider).status == PipelineStatus.success);

      repo.columnsToReturn = [
        testPipelineColumn(leads: [testPipelineLeadCard(id: 'l1'), testPipelineLeadCard(id: 'l2')]),
      ];
      realtime.emitInsert('notifications', {'id': 'n1', 'workspace_id': 'w1'});

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(container.read(pipelineControllerProvider).columns.first.leads, hasLength(1));
    });
  });
}
