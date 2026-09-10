import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/leads/domain/entities/lead_detail_state.dart';
import 'package:mobile/features/leads/domain/entities/tag.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_lead_repository.dart';
import 'lead_test_container.dart';

void main() {
  group('LeadDetailController', () {
    test('loads the lead and its interaction history', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Acme Corp');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);

      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      expect(container.read(leadDetailControllerProvider('l1')).lead?.name, 'Acme Corp');
    });

    test('a NotFoundException lands in notFound, not error', () async {
      final leadRepo = FakeLeadRepository()..getError = const NotFoundException('Lead not found.');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('missing')).close);

      await waitUntil(() => container.read(leadDetailControllerProvider('missing')).status == LeadDetailStatus.notFound);
    });

    test('a permission error lands in error with its message', () async {
      final leadRepo = FakeLeadRepository()..getError = const PermissionDeniedException('You do not have permission to do that.');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);

      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.error);
      expect(container.read(leadDetailControllerProvider('l1')).errorMessage, 'You do not have permission to do that.');
    });

    test('addTag appends the tag to the lead on success', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      final ok = await container.read(leadDetailControllerProvider('l1').notifier).addTag(const Tag(id: 't1', name: 'VIP'));

      expect(ok, isTrue);
      expect(container.read(leadDetailControllerProvider('l1')).lead?.tags.map((t) => t.name), contains('VIP'));
    });

    test('removeTag drops the tag from the lead on success', () async {
      final leadRepo = FakeLeadRepository()
        ..leadToReturn = testLead(id: 'l1', tags: const [Tag(id: 't1', name: 'VIP')]);
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      final ok = await container.read(leadDetailControllerProvider('l1').notifier).removeTag(const Tag(id: 't1', name: 'VIP'));

      expect(ok, isTrue);
      expect(container.read(leadDetailControllerProvider('l1')).lead?.tags, isEmpty);
    });

    test('deleteLead returns true on success', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      final ok = await container.read(leadDetailControllerProvider('l1').notifier).deleteLead();

      expect(ok, isTrue);
      expect(leadRepo.deleteCalled, isTrue);
    });

    test('deleteLead returns false and surfaces the error on failure', () async {
      final leadRepo = FakeLeadRepository()
        ..leadToReturn = testLead(id: 'l1')
        ..deleteError = const PermissionDeniedException('Missing permission: leads.delete');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      final ok = await container.read(leadDetailControllerProvider('l1').notifier).deleteLead();

      expect(ok, isFalse);
      expect(container.read(leadDetailControllerProvider('l1')).errorMessage, 'Missing permission: leads.delete');
    });

    test('loads allocation history alongside the lead', () async {
      final leadRepo = FakeLeadRepository()
        ..leadToReturn = testLead(id: 'l1')
        ..allocationsToReturn = [testAllocation(id: 'a1')];
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);

      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      expect(container.read(leadDetailControllerProvider('l1')).allocations.map((a) => a.id), ['a1']);
    });

    test('assignLead updates the lead and refreshes allocation history on success', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      leadRepo.allocationsToReturn = [testAllocation(id: 'a1', assignedMember: testMember('m2', 'Rep Two'))];
      final ok = await container.read(leadDetailControllerProvider('l1').notifier).assignLead('m2');

      expect(ok, isTrue);
      expect(leadRepo.lastAssignedMemberId, 'm2');
      final state = container.read(leadDetailControllerProvider('l1'));
      expect(state.lead?.assignedMember?.id, 'm2');
      expect(state.allocations.map((a) => a.id), ['a1']);
    });

    test('assignLead(null) unassigns the lead', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      final ok = await container.read(leadDetailControllerProvider('l1').notifier).assignLead(null);

      expect(ok, isTrue);
      expect(leadRepo.lastAssignedMemberId, isNull);
      expect(leadRepo.lastAssignCalled, isTrue);
      expect(container.read(leadDetailControllerProvider('l1')).lead?.assignedMember, isNull);
    });

    test('assignLead returns false and surfaces a permission-denied message on failure', () async {
      final leadRepo = FakeLeadRepository()
        ..leadToReturn = testLead(id: 'l1')
        ..assignError = const PermissionDeniedException('Missing permission: leads.assign');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      final ok = await container.read(leadDetailControllerProvider('l1').notifier).assignLead('m2');

      expect(ok, isFalse);
      expect(container.read(leadDetailControllerProvider('l1')).errorMessage, 'Missing permission: leads.assign');
    });

    test('convertToCustomer swaps in the returned (now-customer) lead on success', () async {
      final leadRepo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', isCustomer: false);
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      final ok = await container.read(leadDetailControllerProvider('l1').notifier).convertToCustomer();

      expect(ok, isTrue);
      expect(leadRepo.lastConvertCalled, isTrue);
      expect(container.read(leadDetailControllerProvider('l1')).lead?.isCustomer, isTrue);
    });

    test('convertToCustomer returns false and surfaces a conflict message on an already-converted lead', () async {
      final leadRepo = FakeLeadRepository()
        ..leadToReturn = testLead(id: 'l1', isCustomer: false)
        ..convertError = const ConflictException('This lead has already been converted to a customer.');
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadDetailControllerProvider('l1')).close);
      await waitUntil(() => container.read(leadDetailControllerProvider('l1')).status == LeadDetailStatus.success);

      final ok = await container.read(leadDetailControllerProvider('l1').notifier).convertToCustomer();

      expect(ok, isFalse);
      expect(container.read(leadDetailControllerProvider('l1')).errorMessage, 'This lead has already been converted to a customer.');
      // The lead in state is untouched by the failed attempt.
      expect(container.read(leadDetailControllerProvider('l1')).lead?.isCustomer, isFalse);
    });
  });
}
