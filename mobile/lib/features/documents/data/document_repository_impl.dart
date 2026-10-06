import '../../../services/api/document_api_data_source.dart';
import '../domain/entities/document.dart';
import '../domain/entities/document_page.dart';
import '../domain/entities/picked_document_file.dart';
import '../domain/repositories/document_repository.dart';

class DocumentRepositoryImpl implements DocumentRepository {
  DocumentRepositoryImpl(this._dataSource);

  final DocumentApiDataSource _dataSource;

  @override
  Future<DocumentPage> listDocuments({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  }) async {
    final json = await _dataSource.listDocuments(
      accessToken: accessToken,
      workspaceId: workspaceId,
      leadId: leadId,
      limit: limit,
      offset: offset,
    );
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(Document.fromJson).toList();
    return DocumentPage(items: items, total: json['total'] as int? ?? items.length, limit: json['limit'] as int? ?? limit, offset: json['offset'] as int? ?? offset);
  }

  @override
  Future<Document> uploadDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required PickedDocumentFile file,
  }) async {
    final json = await _dataSource.uploadDocument(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId, file: file);
    return Document.fromJson(json);
  }

  @override
  Future<String> getSignedUrl({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  }) async {
    final json = await _dataSource.getSignedUrl(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId, documentId: documentId);
    return json['url'] as String;
  }

}
