import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/leads/domain/entities/lead_import_state.dart';
import 'package:mobile/features/leads/presentation/controllers/csv_file_picker.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';

import 'fake_csv_file_picker.dart';
import 'fake_lead_repository.dart';
import 'lead_test_container.dart';

void main() {
  group('LeadImportController', () {
    test('pickFile stores the picked file name and content without uploading', () async {
      final picker = FakeCsvFilePicker()..fileToReturn = const PickedCsvFile(fileName: 'leads.csv', content: 'name\nAcme Corp\n');
      final container = await buildLeadTestContainer(csvFilePicker: picker);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadImportControllerProvider).close);

      await container.read(leadImportControllerProvider.notifier).pickFile();

      final state = container.read(leadImportControllerProvider);
      expect(state.fileName, 'leads.csv');
      expect(state.csvContent, 'name\nAcme Corp\n');
      expect(state.status, LeadImportStatus.idle);
    });

    test('pickFile cancelled by the user leaves the state untouched', () async {
      final picker = FakeCsvFilePicker(); // fileToReturn left null == cancelled
      final container = await buildLeadTestContainer(csvFilePicker: picker);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadImportControllerProvider).close);

      await container.read(leadImportControllerProvider.notifier).pickFile();

      final state = container.read(leadImportControllerProvider);
      expect(state.fileName, isNull);
      expect(state.csvContent, isNull);
    });

    test('pickFile surfaces an error if the file could not be read', () async {
      final picker = FakeCsvFilePicker()..errorToThrow = Exception('boom');
      final container = await buildLeadTestContainer(csvFilePicker: picker);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadImportControllerProvider).close);

      await container.read(leadImportControllerProvider.notifier).pickFile();

      final state = container.read(leadImportControllerProvider);
      expect(state.status, LeadImportStatus.error);
      expect(state.errorMessage, 'Could not read the selected file.');
    });

    test('import uploads the picked csv content and lands in success with the summary', () async {
      final picker = FakeCsvFilePicker()..fileToReturn = const PickedCsvFile(fileName: 'leads.csv', content: 'name\nAcme Corp\n');
      final leadRepo = FakeLeadRepository()
        ..importResultToReturn = const LeadImportResult(total: 1, created: 1, failed: 0, errors: []);
      final container = await buildLeadTestContainer(leadRepository: leadRepo, csvFilePicker: picker);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadImportControllerProvider).close);
      final notifier = container.read(leadImportControllerProvider.notifier);
      await notifier.pickFile();

      await notifier.import();

      expect(leadRepo.lastImportCsvContent, 'name\nAcme Corp\n');
      final state = container.read(leadImportControllerProvider);
      expect(state.status, LeadImportStatus.success);
      expect(state.result?.created, 1);
    });

    test('import with row-level failures still lands in success, carrying the row errors', () async {
      final picker = FakeCsvFilePicker()..fileToReturn = const PickedCsvFile(fileName: 'leads.csv', content: 'name\n,New\n');
      final leadRepo = FakeLeadRepository()
        ..importResultToReturn = const LeadImportResult(
          total: 1,
          created: 0,
          failed: 1,
          errors: [LeadImportRowError(row: 2, error: 'name is required.')],
        );
      final container = await buildLeadTestContainer(leadRepository: leadRepo, csvFilePicker: picker);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadImportControllerProvider).close);
      final notifier = container.read(leadImportControllerProvider.notifier);
      await notifier.pickFile();

      await notifier.import();

      final state = container.read(leadImportControllerProvider);
      expect(state.status, LeadImportStatus.success);
      expect(state.result?.failed, 1);
      expect(state.result?.errors.single.error, 'name is required.');
    });

    test('a network failure during import lands in error with the exception message', () async {
      final picker = FakeCsvFilePicker()..fileToReturn = const PickedCsvFile(fileName: 'leads.csv', content: 'name\nAcme Corp\n');
      final leadRepo = FakeLeadRepository()..importError = const NetworkException('Could not reach the server.');
      final container = await buildLeadTestContainer(leadRepository: leadRepo, csvFilePicker: picker);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadImportControllerProvider).close);
      final notifier = container.read(leadImportControllerProvider.notifier);
      await notifier.pickFile();

      await notifier.import();

      final state = container.read(leadImportControllerProvider);
      expect(state.status, LeadImportStatus.error);
      expect(state.errorMessage, 'Could not reach the server.');
    });

    test('import without a picked file is a no-op', () async {
      final leadRepo = FakeLeadRepository();
      final container = await buildLeadTestContainer(leadRepository: leadRepo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, leadImportControllerProvider).close);

      await container.read(leadImportControllerProvider.notifier).import();

      expect(leadRepo.lastImportCsvContent, isNull);
      expect(container.read(leadImportControllerProvider).status, LeadImportStatus.idle);
    });
  });
}
