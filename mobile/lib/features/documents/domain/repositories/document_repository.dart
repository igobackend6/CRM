import '../entities/document.dart';
import '../entities/document_page.dart';
import '../entities/picked_document_file.dart';

abstract class DocumentRepository {
  Future<DocumentPage> listDocuments({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  });

  Future<Document> uploadDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required PickedDocumentFile file,
  });

  /// A fresh, short-lived signed URL (§3 "Preview"/"Download") — never
  /// cached across calls, since it expires server-side after a few
  /// minutes (DocumentService.SIGNED_URL_EXPIRES_IN_SECONDS).
  Future<String> getSignedUrl({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  });

}
