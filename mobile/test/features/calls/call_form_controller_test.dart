import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/calls/domain/entities/call_draft.dart';
import 'package:mobile/features/calls/domain/entities/call_form_state.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';

import 'call_test_container.dart';
import 'fake_call_repository.dart';

void main() {
  group('CallFormController', () {
    test('create succeeds and stores the logged call', () async {
      final repo = FakeCallRepository();
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callFormControllerProvider).close);

      await container
          .read(callFormControllerProvider.notifier)
          .create('l1', const CallDraft(direction: 'outbound', notes: 'Discussed pricing', durationSeconds: 90));

      expect(repo.lastCreateLeadId, 'l1');
      expect(repo.lastCreateDraft?.durationSeconds, 90);
      expect(container.read(callFormControllerProvider).status, CallFormStatus.success);
    });

    test('create surfaces a validation error (e.g. invalid outcome)', () async {
      final repo = FakeCallRepository()..createError = const ValidationException('Selected outcome is not valid for this workspace.');
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callFormControllerProvider).close);

      await container.read(callFormControllerProvider.notifier).create('l1', const CallDraft(direction: 'outbound', outcomeId: 'bad'));

      expect(container.read(callFormControllerProvider).status, CallFormStatus.error);
      expect(container.read(callFormControllerProvider).errorMessage, 'Selected outcome is not valid for this workspace.');
    });

    test('create surfaces a cross-workspace lead rejection as not-found', () async {
      final repo = FakeCallRepository()..createError = const NotFoundException('Lead not found.');
      final container = await buildCallTestContainer(callRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, callFormControllerProvider).close);

      await container.read(callFormControllerProvider.notifier).create('other-workspace-lead', const CallDraft(direction: 'outbound'));

      expect(container.read(callFormControllerProvider).status, CallFormStatus.error);
      expect(container.read(callFormControllerProvider).errorMessage, 'Lead not found.');
    });
  });
}
