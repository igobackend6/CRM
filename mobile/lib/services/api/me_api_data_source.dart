import 'package:dio/dio.dart';

import 'api_client.dart';

/// Outcome of calling the backend's GET /api/v1/me — see Phase 4 spec
/// §12 for the exact four cases this must distinguish.
sealed class BackendMeResult {
  const BackendMeResult();
}

final class BackendMeSuccess extends BackendMeResult {
  const BackendMeSuccess(this.data);
  final Map<String, dynamic> data;
}

/// 401 — session invalid, caller should sign the user out.
final class BackendMeUnauthorized extends BackendMeResult {
  const BackendMeUnauthorized();
}

/// 403 — permission/access problem.
final class BackendMeForbidden extends BackendMeResult {
  const BackendMeForbidden();
}

/// Timeout, no connection, DNS failure, 5xx, or anything else that's
/// worth retrying rather than treating as an auth failure.
final class BackendMeNetworkError extends BackendMeResult {
  const BackendMeNetworkError(this.message);
  final String message;
}

abstract class MeApiDataSource {
  Future<BackendMeResult> fetchMe(String accessToken);
}

/// Pure mapping from a DioException to a BackendMeResult — split out so
/// it's testable without any real HTTP transport.
BackendMeResult mapDioExceptionToMeResult(DioException error) {
  final statusCode = error.response?.statusCode;
  if (statusCode == 401) return const BackendMeUnauthorized();
  if (statusCode == 403) return const BackendMeForbidden();
  return BackendMeNetworkError(error.message ?? 'Network error contacting the backend.');
}

class DioMeApiDataSource implements MeApiDataSource {
  DioMeApiDataSource([Dio? dio]) : _dio = dio ?? ApiClient.instance;

  final Dio _dio;

  @override
  Future<BackendMeResult> fetchMe(String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/me',
        options: ApiClient.authOptions(accessToken),
      );
      return BackendMeSuccess(response.data ?? const {});
    } on DioException catch (error) {
      return mapDioExceptionToMeResult(error);
    }
  }
}
