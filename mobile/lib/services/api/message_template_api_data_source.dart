import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for `/api/v1/workspaces/{workspace_id}/message-templates`
/// (backend/app/api/v1/message_templates.py).
abstract class MessageTemplateApiDataSource {
  Future<List<dynamic>> listTemplates({required String accessToken, required String workspaceId});

  Future<Map<String, dynamic>> createTemplate({
    required String accessToken,
    required String workspaceId,
    required String name,
    required String body,
  });

  Future<Map<String, dynamic>> updateTemplate({
    required String accessToken,
    required String workspaceId,
    required String templateId,
    Map<String, dynamic>? changes,
  });

  Future<void> deleteTemplate({required String accessToken, required String workspaceId, required String templateId});
}

class DioMessageTemplateApiDataSource implements MessageTemplateApiDataSource {
  DioMessageTemplateApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId/message-templates';

  @override
  Future<List<dynamic>> listTemplates({required String accessToken, required String workspaceId}) async {
    try {
      final response = await _dio.get<List<dynamic>>(_base(workspaceId), options: ApiClient.authOptions(accessToken));
      return response.data ?? const [];
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> createTemplate({
    required String accessToken,
    required String workspaceId,
    required String name,
    required String body,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _base(workspaceId),
        data: {'name': name, 'body': body},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> updateTemplate({
    required String accessToken,
    required String workspaceId,
    required String templateId,
    Map<String, dynamic>? changes,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '${_base(workspaceId)}/$templateId',
        data: changes ?? const {},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<void> deleteTemplate({required String accessToken, required String workspaceId, required String templateId}) async {
    try {
      await _dio.delete<void>('${_base(workspaceId)}/$templateId', options: ApiClient.authOptions(accessToken));
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
