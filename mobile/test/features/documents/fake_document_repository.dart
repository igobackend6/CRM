import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/documents/domain/entities/document.dart';
import 'package:mobile/features/documents/domain/entities/document_page.dart';
import 'package:mobile/features/documents/domain/entities/picked_document_file.dart';
import 'package:mobile/features/documents/domain/repositories/document_repository.dart';

/// Shared fake, used both by documents-feature-specific tests and by
/// every other lead-detail-pumping widget test (calls/followups/
/// messaging/customer360-nav/ai/assignment/activity/conversion) so
/// DocumentsSection's own real fetch never reaches a real network call
/// — same role FakeAiInsightRepository plays for LeadAiSection.
class FakeDocumentRepository implements DocumentRepository {
  List<Document> documentsToReturn = const [];
  int documentsTotalToReturn = 0;
  AppException? listError;

  Document? uploadResult;
  AppException? uploadError;

  String signedUrlToReturn = 'https://signed.example/file.pdf';
  AppException? signedUrlError;

  AppException? deleteError;

  int? lastListOffset;
  PickedDocumentFile? lastUploadedFile;
  String? lastDeletedDocumentId;

  @override
  Future<DocumentPage> listDocuments({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  }) async {
    lastListOffset = offset;
    if (listError != null) throw listError!;
    return DocumentPage(items: documentsToReturn, total: documentsTotalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<Document> uploadDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required PickedDocumentFile file,
  }) async {
    lastUploadedFile = file;
    if (uploadError != null) throw uploadError!;
    return uploadResult ?? Document(id: 'uploaded', fileName: file.fileName, createdAt: DateTime.utc(2026, 1, 1));
  }

  @override
  Future<String> getSignedUrl({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  }) async {
    if (signedUrlError != null) throw signedUrlError!;
    return signedUrlToReturn;
  }

  @override
  Future<void> deleteDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  }) async {
    lastDeletedDocumentId = documentId;
    if (deleteError != null) throw deleteError!;
  }
}
