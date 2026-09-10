import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/documents/data/document_repository_impl.dart';
import 'package:mobile/features/documents/domain/entities/picked_document_file.dart';

import 'fake_document_api_data_source.dart';

void main() {
  group('DocumentRepositoryImpl', () {
    test('listDocuments maps items and total', () async {
      final dataSource = FakeDocumentApiDataSource()
        ..listDocumentsResponse = {
          'items': [
            {
              'id': 'd1',
              'file_name': 'contract.pdf',
              'mime_type': 'application/pdf',
              'size_bytes': 2048,
              'uploaded_by_member': {'id': 'm1', 'full_name': 'Rep One'},
              'created_at': '2026-01-01T00:00:00Z',
            },
          ],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = DocumentRepositoryImpl(dataSource);

      final page = await repo.listDocuments(accessToken: 't', workspaceId: 'w1', leadId: 'l1', limit: 20, offset: 0);

      expect(page.items, hasLength(1));
      expect(page.items.first.fileName, 'contract.pdf');
      expect(page.total, 1);
    });

    test('uploadDocument sends the picked file and maps the created row', () async {
      final dataSource = FakeDocumentApiDataSource()
        ..uploadDocumentResponse = {
          'id': 'd1',
          'file_name': 'contract.pdf',
          'mime_type': 'application/pdf',
          'size_bytes': 3,
          'created_at': '2026-01-01T00:00:00Z',
        };
      final repo = DocumentRepositoryImpl(dataSource);
      const file = PickedDocumentFile(fileName: 'contract.pdf', bytes: [1, 2, 3], mimeType: 'application/pdf');

      final document = await repo.uploadDocument(accessToken: 't', workspaceId: 'w1', leadId: 'l1', file: file);

      expect(document.fileName, 'contract.pdf');
      expect(dataSource.lastUploadedFile, same(file));
    });

    test('getSignedUrl returns the url field', () async {
      final dataSource = FakeDocumentApiDataSource()..getSignedUrlResponse = {'url': 'https://signed.example/d1', 'expires_in': 300};
      final repo = DocumentRepositoryImpl(dataSource);

      final url = await repo.getSignedUrl(accessToken: 't', workspaceId: 'w1', leadId: 'l1', documentId: 'd1');

      expect(url, 'https://signed.example/d1');
    });

    test('deleteDocument forwards the document id', () async {
      final dataSource = FakeDocumentApiDataSource();
      final repo = DocumentRepositoryImpl(dataSource);

      await repo.deleteDocument(accessToken: 't', workspaceId: 'w1', leadId: 'l1', documentId: 'd1');

      expect(dataSource.lastDeletedDocumentId, 'd1');
    });
  });
}
