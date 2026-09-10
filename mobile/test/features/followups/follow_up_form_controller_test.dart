import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/followups/domain/entities/follow_up_draft.dart';
import 'package:mobile/features/followups/domain/entities/follow_up_form_state.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';

import 'fake_follow_up_repository.dart';
import 'followup_test_container.dart';

void main() {
  group('FollowUpFormController', () {
    test('create succeeds and stores the created follow-up', () async {
      final repo = FakeFollowUpRepository();
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpFormControllerProvider).close);

      await container.read(followUpFormControllerProvider.notifier).create(
            'l1',
            FollowUpDraft(dueAt: DateTime.utc(2026, 2, 1, 9), type: 'call', notes: 'Confirm budget'),
          );

      expect(repo.lastCreateLeadId, 'l1');
      expect(container.read(followUpFormControllerProvider).status, FollowUpFormStatus.success);
    });

    test('create surfaces a validation error', () async {
      final repo = FakeFollowUpRepository()..createError = const ValidationException('type must be one of the supported types.');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpFormControllerProvider).close);

      await container.read(followUpFormControllerProvider.notifier).create(
            'l1',
            FollowUpDraft(dueAt: DateTime.utc(2026, 2, 1, 9), type: 'call'),
          );

      expect(container.read(followUpFormControllerProvider).status, FollowUpFormStatus.error);
      expect(container.read(followUpFormControllerProvider).errorMessage, 'type must be one of the supported types.');
    });

    test('update reschedules and changes status in one call', () async {
      final repo = FakeFollowUpRepository();
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpFormControllerProvider).close);

      await container.read(followUpFormControllerProvider.notifier).update(
            'fu-1',
            FollowUpDraft(dueAt: DateTime.utc(2026, 3, 1, 10), type: 'meeting', status: 'completed'),
          );

      expect(repo.lastUpdateFollowUpId, 'fu-1');
      expect(repo.lastUpdateDraft?.status, 'completed');
      final state = container.read(followUpFormControllerProvider);
      expect(state.status, FollowUpFormStatus.success);
      expect(state.followUp?.status, 'completed');
    });

    test('update surfaces a permission-denied error', () async {
      final repo = FakeFollowUpRepository()..updateError = const PermissionDeniedException('Missing permission: followups.update');
      final container = await buildFollowUpTestContainer(followUpRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, followUpFormControllerProvider).close);

      await container.read(followUpFormControllerProvider.notifier).update(
            'fu-1',
            FollowUpDraft(dueAt: DateTime.utc(2026, 2, 1, 9), type: 'call'),
          );

      expect(container.read(followUpFormControllerProvider).status, FollowUpFormStatus.error);
      expect(container.read(followUpFormControllerProvider).errorMessage, 'Missing permission: followups.update');
    });
  });
}
