import 'package:dio/dio.dart';

import '../../features/documents/domain/entities/picked_document_file.dart';
import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI Secure Lead Documents surface
/// (`/api/v1/workspaces/{workspace_id}/leads/{lead_id}/documents` —
/// backend/app/api/v1/documents.py). Kept table-agnostic about domain
/// entities on purpose, same split as every other *ApiDataSource in
/// this app.
abstract class DocumentApiDataSource {
  Future<Map<String, dynamic>> listDocuments({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> uploadDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required PickedDocumentFile file,
  });

  Future<Map<String, dynamic>> getSignedUrl({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  });

  Future<void> deleteDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  });
}

class DioDocumentApiDataSource implements DocumentApiDataSource {
  DioDocumentApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId, String leadId) => '/api/v1/workspaces/$workspaceId/leads/$leadId/documents';

  @override
  Future<Map<String, dynamic>> listDocuments({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _base(workspaceId, leadId),
        queryParameters: {'limit': limit, 'offset': offset},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> uploadDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required PickedDocumentFile file,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(file.bytes, filename: file.fileName, contentType: DioMediaType.parse(file.mimeType)),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        _base(workspaceId, leadId),
        data: formData,
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getSignedUrl({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId, leadId)}/$documentId/signed-url',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<void> deleteDocument({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String documentId,
  }) async {
    try {
      await _dio.delete<void>('${_base(workspaceId, leadId)}/$documentId', options: ApiClient.authOptions(accessToken));
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
