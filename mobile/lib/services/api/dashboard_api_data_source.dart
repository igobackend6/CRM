import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI dashboard surface
/// (`/api/v1/workspaces/{workspace_id}/dashboard/...` —
/// backend/app/api/v1/dashboard.py). Kept table-agnostic about domain
/// entities, same split as every other *_api_data_source.dart in this
/// app — converting JSON <-> DashboardSummary/RecentActivityItem is
/// DashboardRepositoryImpl's job.
abstract class DashboardApiDataSource {
  Future<Map<String, dynamic>> getSummary({required String accessToken, required String workspaceId, String range = 'all'});

  Future<Map<String, dynamic>> getRecentActivity({
    required String accessToken,
    required String workspaceId,
    required int limit,
    required int offset,
  });
}

class DioDashboardApiDataSource implements DashboardApiDataSource {
  DioDashboardApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  @override
  Future<Map<String, dynamic>> getSummary({required String accessToken, required String workspaceId, String range = 'all'}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/dashboard/summary',
        queryParameters: {'range': range},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getRecentActivity({
    required String accessToken,
    required String workspaceId,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/dashboard/recent-activity',
        queryParameters: {'limit': limit, 'offset': offset},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
