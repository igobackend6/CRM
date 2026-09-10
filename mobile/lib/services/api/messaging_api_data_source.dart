import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI messaging surface
/// (`/api/v1/workspaces/{workspace_id}/...` —
/// backend/app/api/v1/messages.py). Kept table-agnostic about domain
/// entities, same split as call_api_data_source.dart — converting JSON
/// <-> Conversation/Message is MessagingRepositoryImpl's job.
abstract class MessagingApiDataSource {
  Future<Map<String, dynamic>> listConversations({
    required String accessToken,
    required String workspaceId,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> getOrCreateConversation({
    required String accessToken,
    required String workspaceId,
    required String leadId,
  });

  Future<Map<String, dynamic>> listMessages({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> sendMessage({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required String body,
  });

  Future<void> markConversationRead({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
  });
}

class DioMessagingApiDataSource implements MessagingApiDataSource {
  DioMessagingApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>> listConversations({
    required String accessToken,
    required String workspaceId,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/conversations',
        queryParameters: {'limit': limit, 'offset': offset},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getOrCreateConversation({
    required String accessToken,
    required String workspaceId,
    required String leadId,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/leads/$leadId/conversation',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> listMessages({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/conversations/$conversationId/messages',
        queryParameters: {'limit': limit, 'offset': offset},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required String body,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/conversations/$conversationId/messages',
        data: {'body': body},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<void> markConversationRead({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/conversations/$conversationId/read',
        options: ApiClient.authOptions(accessToken),
      );
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
