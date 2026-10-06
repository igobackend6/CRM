import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_error_mapper.dart';

/// Raw JSON in/out for the FastAPI Login Analytics surface
/// (`/api/v1/workspaces/{workspace_id}/activity/...` —
/// backend/app/api/v1/activity.py). Same split as every other
/// `*_api_data_source.dart`: JSON <-> entities is the repository's job.
abstract class ActivityApiDataSource {
  /// The running app checking in (about once a minute).
  Future<Map<String, dynamic>> heartbeat({required String accessToken, required String workspaceId, required int utcOffsetMinutes});

  Future<Map<String, dynamic>> signOut({required String accessToken, required String workspaceId, required int utcOffsetMinutes});

  Future<Map<String, dynamic>> startBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes});

  Future<Map<String, dynamic>> endBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes});

  Future<Map<String, dynamic>> getSummary({
    required String accessToken,
    required String workspaceId,
    required DateTime since,
    required DateTime until,
  });
}

class DioActivityApiDataSource implements ActivityApiDataSource {
  DioActivityApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  String _base(String workspaceId) => '/api/v1/workspaces/$workspaceId/activity';

  Future<Map<String, dynamic>> _post(String path, String accessToken, int utcOffsetMinutes) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: {'utc_offset_minutes': utcOffsetMinutes},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> heartbeat({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) =>
      _post('${_base(workspaceId)}/heartbeat', accessToken, utcOffsetMinutes);

  @override
  Future<Map<String, dynamic>> signOut({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) =>
      _post('${_base(workspaceId)}/sign-out', accessToken, utcOffsetMinutes);

  @override
  Future<Map<String, dynamic>> startBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) =>
      _post('${_base(workspaceId)}/break/start', accessToken, utcOffsetMinutes);

  @override
  Future<Map<String, dynamic>> endBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) =>
      _post('${_base(workspaceId)}/break/end', accessToken, utcOffsetMinutes);

  @override
  Future<Map<String, dynamic>> getSummary({
    required String accessToken,
    required String workspaceId,
    required DateTime since,
    required DateTime until,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_base(workspaceId)}/summary',
        queryParameters: {'since': since.toUtc().toIso8601String(), 'until': until.toUtc().toIso8601String()},
        options: ApiClient.authOptions(accessToken),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      throw mapDioExceptionToAppException(e);
    }
  }
}
