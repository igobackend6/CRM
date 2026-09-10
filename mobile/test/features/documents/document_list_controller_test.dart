import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/utils/external_url_launcher.dart';
import 'package:mobile/features/documents/data/document_file_picker.dart';
import 'package:mobile/features/documents/domain/entities/document.dart';
import 'package:mobile/features/documents/domain/entities/document_list_state.dart';
import 'package:mobile/features/documents/domain/entities/picked_document_file.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';

import 'documents_test_container.dart';
import 'fake_document_repository.dart';

class _FakeDocumentFilePicker implements DocumentFilePicker {
  PickedDocumentFile? fileToReturn;

  @override
  Future<PickedDocumentFile?> pickDocumentFile() async => fileToReturn;
}

class _FakeExternalUrlLauncher implements ExternalUrlLauncher {
  bool shouldSucceed = true;
  Uri? lastLaunchedUri;

  @override
  Future<bool> launch(Uri uri) async {
    lastLaunchedUri = uri;
    return shouldSucceed;
  }
}

Document _document(String id) => Document(id: id, fileName: '$id.pdf', createdAt: DateTime.utc(2026, 1, 1));

void main() {
  group('DocumentListController', () {
    test('refresh loads the first page', () async {
      final repo = FakeDocumentRepository()
        ..documentsToReturn = [_document('d1')]
        ..documentsTotalToReturn = 1;
      final container = await buildDocumentsTestContainer(documentRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);

      await container.read(documentListControllerProvider('l1').notifier).refresh();

      final state = container.read(documentListControllerProvider('l1'));
      expect(state.status, DocumentListStatus.success);
      expect(state.items, hasLength(1));
    });

    test('an empty result is represented as the empty status', () async {
      final container = await buildDocumentsTestContainer();
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);

      await container.read(documentListControllerProvider('l1').notifier).refresh();

      expect(container.read(documentListControllerProvider('l1')).status, DocumentListStatus.empty);
    });

    test('loadMore appends the next page', () async {
      final repo = FakeDocumentRepository()
        ..documentsToReturn = [_document('d1')]
        ..documentsTotalToReturn = 2;
      final container = await buildDocumentsTestContainer(documentRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);
      await container.read(documentListControllerProvider('l1').notifier).refresh();

      repo.documentsToReturn = [_document('d2')];
      await container.read(documentListControllerProvider('l1').notifier).loadMore();

      final state = container.read(documentListControllerProvider('l1'));
      expect(state.items.map((d) => d.id), ['d1', 'd2']);
      expect(state.hasMore, isFalse);
    });

    test('a load error surfaces the message', () async {
      final repo = FakeDocumentRepository()..listError = const NetworkException('offline');
      final container = await buildDocumentsTestContainer(documentRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);

      await container.read(documentListControllerProvider('l1').notifier).refresh();

      final state = container.read(documentListControllerProvider('l1'));
      expect(state.status, DocumentListStatus.error);
      expect(state.errorMessage, 'offline');
    });

    test('pickAndUpload does nothing when the user cancels the picker', () async {
      final repo = FakeDocumentRepository();
      final container = await buildDocumentsTestContainer(documentRepository: repo, filePicker: _FakeDocumentFilePicker());
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);

      await container.read(documentListControllerProvider('l1').notifier).pickAndUpload();

      expect(repo.lastUploadedFile, isNull);
      expect(container.read(documentListControllerProvider('l1')).uploading, isFalse);
    });

    test('pickAndUpload prepends the new document on success', () async {
      final repo = FakeDocumentRepository()..uploadResult = _document('new-doc');
      final picker = _FakeDocumentFilePicker()
        ..fileToReturn = const PickedDocumentFile(fileName: 'contract.pdf', bytes: [1, 2, 3], mimeType: 'application/pdf');
      final container = await buildDocumentsTestContainer(documentRepository: repo, filePicker: picker);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);

      await container.read(documentListControllerProvider('l1').notifier).pickAndUpload();

      final state = container.read(documentListControllerProvider('l1'));
      expect(state.items.first.id, 'new-doc');
      expect(state.total, 1);
      expect(state.uploading, isFalse);
      expect(repo.lastUploadedFile?.fileName, 'contract.pdf');
    });

    test('pickAndUpload surfaces a validation error (e.g. disallowed type) without adding an item', () async {
      final repo = FakeDocumentRepository()..uploadError = const ValidationException('File type is not allowed.');
      final picker = _FakeDocumentFilePicker()
        ..fileToReturn = const PickedDocumentFile(fileName: 'virus.exe', bytes: [1], mimeType: 'application/x-msdownload');
      final container = await buildDocumentsTestContainer(documentRepository: repo, filePicker: picker);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);

      await container.read(documentListControllerProvider('l1').notifier).pickAndUpload();

      final state = container.read(documentListControllerProvider('l1'));
      expect(state.items, isEmpty);
      expect(state.uploadError, 'File type is not allowed.');
    });

    test('openDocument launches the signed URL and reports success', () async {
      final repo = FakeDocumentRepository()..signedUrlToReturn = 'https://signed.example/report.pdf';
      final launcher = _FakeExternalUrlLauncher();
      final container = await buildDocumentsTestContainer(documentRepository: repo, launcher: launcher);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);

      final ok = await container.read(documentListControllerProvider('l1').notifier).openDocument('d1');

      expect(ok, isTrue);
      expect(launcher.lastLaunchedUri, Uri.parse('https://signed.example/report.pdf'));
    });

    test('openDocument returns false when the launcher cannot open the URL', () async {
      final repo = FakeDocumentRepository();
      final launcher = _FakeExternalUrlLauncher()..shouldSucceed = false;
      final container = await buildDocumentsTestContainer(documentRepository: repo, launcher: launcher);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);

      expect(await container.read(documentListControllerProvider('l1').notifier).openDocument('d1'), isFalse);
    });

    test('deleteDocument removes the item from state', () async {
      final repo = FakeDocumentRepository()
        ..documentsToReturn = [_document('d1')]
        ..documentsTotalToReturn = 1;
      final container = await buildDocumentsTestContainer(documentRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);
      await container.read(documentListControllerProvider('l1').notifier).refresh();

      await container.read(documentListControllerProvider('l1').notifier).deleteDocument('d1');

      final state = container.read(documentListControllerProvider('l1'));
      expect(state.items, isEmpty);
      expect(state.status, DocumentListStatus.empty);
      expect(repo.lastDeletedDocumentId, 'd1');
    });

    test('a delete failure surfaces the error message without removing the item', () async {
      final repo = FakeDocumentRepository()
        ..documentsToReturn = [_document('d1')]
        ..documentsTotalToReturn = 1
        ..deleteError = const NetworkException('offline');
      final container = await buildDocumentsTestContainer(documentRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, documentListControllerProvider('l1')).close);
      await container.read(documentListControllerProvider('l1').notifier).refresh();

      await container.read(documentListControllerProvider('l1').notifier).deleteDocument('d1');

      final state = container.read(documentListControllerProvider('l1'));
      expect(state.items, hasLength(1));
      expect(state.errorMessage, 'offline');
    });
  });
}
