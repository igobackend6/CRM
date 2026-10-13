import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import 'retry_interceptor.dart';

/// Centralized Dio client for calling the Python FastAPI backend. Kept
/// out of UI widgets, same rule as SupabaseService — see
/// services/supabase/supabase_service.dart. Every call must carry the
/// current Supabase access token as a Bearer header; this client never
/// holds a static/shared token, since a request-scoped token is the
/// whole point of Phase 3's per-request auth model (see
/// docs/architecture/10-backend-security-implementation.md).
class ApiClient {
  ApiClient._();

  static final Dio _dio = _build();

  static Dio _build() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        // Generous on purpose: a phone on a slow or switching network, or a hosted function waking up
        // after a quiet spell, can legitimately need longer than a desk connection. A truly hung request
        // still ends; the retry interceptor then tries reads again.
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    dio.interceptors.add(RetryInterceptor(dio));
    return dio;
  }

  static Dio get instance => _dio;

  /// Wakes a sleeping hosted backend (and warms the connection) at app start, so the first screen does not
  /// pay for it. Failures are ignored: the screens' own requests (and their retries) take over.
  static Future<void> warmUp() async {
    try {
      await _dio.get<void>('/health', options: Options(receiveTimeout: const Duration(seconds: 20)));
    } catch (_) {}
  }

  /// Options carrying the caller's own bearer token — pass this to
  /// every authenticated request instead of mutating shared headers.
  static Options authOptions(String accessToken) {
    return Options(headers: {'Authorization': 'Bearer $accessToken'});
  }
}
