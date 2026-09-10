import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/followups/domain/entities/follow_up_detail_state.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_follow_up_repository.dart';
import 'followup_test_container.dart';

void main() {
  group('FollowUpDetailController', () {
    test('loads the follow-up', () async {
      final repo = FakeFollowUpRepository()..followUpToReturn = testFollowUp(id: 'fu-1', leadName: 'Acme Corp');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpDetailControllerProvider('fu-1')).close);

      await waitUntil(() => container.read(followUpDetailControllerProvider('fu-1')).status == FollowUpDetailStatus.success);

      expect(container.read(followUpDetailControllerProvider('fu-1')).followUp?.lead.name, 'Acme Corp');
    });

    test('a NotFoundException lands in notFound, not error', () async {
      final repo = FakeFollowUpRepository()..getError = const NotFoundException('Follow-up not found.');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpDetailControllerProvider('missing')).close);

      await waitUntil(() => container.read(followUpDetailControllerProvider('missing')).status == FollowUpDetailStatus.notFound);
    });

    test('a permission error lands in error with its message', () async {
      final repo = FakeFollowUpRepository()..getError = const PermissionDeniedException('You do not have permission to do that.');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpDetailControllerProvider('fu-1')).close);

      await waitUntil(() => container.read(followUpDetailControllerProvider('fu-1')).status == FollowUpDetailStatus.error);
      expect(container.read(followUpDetailControllerProvider('fu-1')).errorMessage, 'You do not have permission to do that.');
    });

    test('updateStatus("completed") marks the follow-up complete', () async {
      final repo = FakeFollowUpRepository()..followUpToReturn = testFollowUp(id: 'fu-1');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpDetailControllerProvider('fu-1')).close);
      await waitUntil(() => container.read(followUpDetailControllerProvider('fu-1')).status == FollowUpDetailStatus.success);

      final ok = await container.read(followUpDetailControllerProvider('fu-1').notifier).updateStatus('completed');

      expect(ok, isTrue);
      expect(repo.lastStatus, 'completed');
      expect(container.read(followUpDetailControllerProvider('fu-1')).followUp?.status, 'completed');
    });

    test('updateStatus("cancelled") cancels the follow-up', () async {
      final repo = FakeFollowUpRepository()..followUpToReturn = testFollowUp(id: 'fu-1');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpDetailControllerProvider('fu-1')).close);
      await waitUntil(() => container.read(followUpDetailControllerProvider('fu-1')).status == FollowUpDetailStatus.success);

      final ok = await container.read(followUpDetailControllerProvider('fu-1').notifier).updateStatus('cancelled');

      expect(ok, isTrue);
      expect(container.read(followUpDetailControllerProvider('fu-1')).followUp?.status, 'cancelled');
    });

    test('updateStatus returns false and surfaces the error on failure', () async {
      final repo = FakeFollowUpRepository()
        ..followUpToReturn = testFollowUp(id: 'fu-1')
        ..statusError = const PermissionDeniedException('Missing permission: followups.update');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpDetailControllerProvider('fu-1')).close);
      await waitUntil(() => container.read(followUpDetailControllerProvider('fu-1')).status == FollowUpDetailStatus.success);

      final ok = await container.read(followUpDetailControllerProvider('fu-1').notifier).updateStatus('completed');

      expect(ok, isFalse);
      expect(container.read(followUpDetailControllerProvider('fu-1')).errorMessage, 'Missing permission: followups.update');
    });
  });
}
