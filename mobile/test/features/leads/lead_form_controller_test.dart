import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/leads/domain/entities/lead_draft.dart';
import 'package:mobile/features/leads/domain/entities/lead_form_state.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';

import 'fake_lead_repository.dart';
import 'lead_test_container.dart';

void main() {
  group('LeadFormController', () {
    test('create() lands in success with the created lead', () async {
      final leadRepo = FakeLeadRepository();
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadFormControllerProvider).close);

      await container.read(leadFormControllerProvider.notifier).create(const LeadDraft(name: 'Acme Corp'));

      final state = container.read(leadFormControllerProvider);
      expect(state.status, LeadFormStatus.success);
      expect(state.lead?.name, 'Acme Corp');
      expect(leadRepo.lastCreateDraft?.name, 'Acme Corp');
    });

    test('create() surfaces a validation error from the repository', () async {
      final leadRepo = FakeLeadRepository()..createError = const ValidationException('Name is required.');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadFormControllerProvider).close);

      await container.read(leadFormControllerProvider.notifier).create(const LeadDraft(name: ''));

      final state = container.read(leadFormControllerProvider);
      expect(state.status, LeadFormStatus.error);
      expect(state.errorMessage, 'Name is required.');
    });

    test('update() lands in success with the updated lead', () async {
      final leadRepo = FakeLeadRepository();
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadFormControllerProvider).close);

      await container.read(leadFormControllerProvider.notifier).update('lead-1', const LeadDraft(name: 'Renamed Co'));

      final state = container.read(leadFormControllerProvider);
      expect(state.status, LeadFormStatus.success);
      expect(state.lead?.name, 'Renamed Co');
      expect(leadRepo.lastUpdateDraft?.name, 'Renamed Co');
    });

    test('update() surfaces a permission error from the repository', () async {
      final leadRepo = FakeLeadRepository()..updateError = const PermissionDeniedException('Missing permission: leads.update');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadFormControllerProvider).close);

      await container.read(leadFormControllerProvider.notifier).update('lead-1', const LeadDraft(name: 'Renamed Co'));

      final state = container.read(leadFormControllerProvider);
      expect(state.status, LeadFormStatus.error);
      expect(state.errorMessage, 'Missing permission: leads.update');
    });
  });
}
