import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI notifications surface
/// (`/api/v1/workspaces/{workspace_id}/notifications...` —
/// backend/app/api/v1/notifications.py). Kept table-agnostic about
/// domain entities, same split as call_api_data_source.dart/
/// follow_up_api_data_source.dart — converting JSON <-> AppNotification
/// is NotificationRepositoryImpl's job.
abstract class NotificationApiDataSource {
  Future<Map<String, dynamic>> listNotifications({
    required String accessToken,
    required String workspaceId,
    bool? isRead,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> markRead({
    required String accessToken,
    required String workspaceId,
    required String notificationId,
    required bool isRead,
  });

  Future<Map<String, dynamic>> markAllRead({required String accessToken, required String workspaceId});
}

class DioNotificationApiDataSource implements NotificationApiDataSource {
  DioNotificationApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>> listNotifications({
    required String accessToken,
    required String workspaceId,
    bool? isRead,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/notifications',
        queryParameters: {
          'is_read': ?isRead,
          'limit': limit,
          'offset': offset,
        },
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> markRead({
    required String accessToken,
    required String workspaceId,
    required String notificationId,
    required bool isRead,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '${_base(workspaceId)}/notifications/$notificationId',
        data: {'is_read': isRead},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> markAllRead({required String accessToken, required String workspaceId}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_base(workspaceId)}/notifications/mark-all-read',
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
