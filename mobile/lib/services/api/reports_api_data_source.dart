import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI reports surface
/// (`/api/v1/workspaces/{workspace_id}/reports/...` —
/// backend/app/api/v1/reports.py). Kept table/entity-agnostic, same
/// split as every other `*_api_data_source.dart` in this app —
/// converting JSON <-> PersonalReport/TeamReportPage/PipelineReport is
/// ReportsRepositoryImpl's job.
abstract class ReportsApiDataSource {
  Future<Map<String, dynamic>> getPersonalReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  });

  Future<Map<String, dynamic>> getTeamReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
    required int limit,
    required int offset,
  });

  Future<Map<String, dynamic>> getPipelineReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  });
}

class DioReportsApiDataSource implements ReportsApiDataSource {
  DioReportsApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId';

  Map<String, dynamic> _rangeParams(String range, DateTime? since, DateTime? until) {
    final params = <String, dynamic>{'range': range};
    if (since != null) params['since'] = since.toUtc().toIso8601String();
    if (until != null) params['until'] = until.toUtc().toIso8601String();
    return params;
  }

  @override
  Future<Map<String, dynamic>> getPersonalReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/reports/personal',
        queryParameters: _rangeParams(range, since, until),
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getTeamReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/reports/team',
        queryParameters: {..._rangeParams(range, since, until), 'limit': limit, 'offset': offset},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getPipelineReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/reports/pipeline',
        queryParameters: _rangeParams(range, since, until),
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
