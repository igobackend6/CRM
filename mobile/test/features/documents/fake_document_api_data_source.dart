import 'package:mobile/features/documents/domain/entities/picked_document_file.dart';
import 'package:mobile/services/api/document_api_data_source.dart';

class FakeDocumentApiDataSource implements DocumentApiDataSource {
  Map<String, dynamic> listDocumentsResponse = const {};
  Map<String, dynamic> uploadDocumentResponse = const {};
  Map<String, dynamic> getSignedUrlResponse = const {};
  Object? errorToThrow;

  PickedDocumentFile? lastUploadedFile;

  @override
  Future<Map<String, dynamic>> listDocuments({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    return listDocumentsResponse;
  }

  @override
  Future<Map<String, dynamic>> uploadDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required PickedDocumentFile file,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastUploadedFile = file;
    return uploadDocumentResponse;
  }

  @override
  Future<Map<String, dynamic>> getSignedUrl({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    return getSignedUrlResponse;
  }

}
