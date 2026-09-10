import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';

/// Centralized Dio client for calling the Python FastAPI backend. Kept
/// out of UI widgets, same rule as SupabaseService — see
/// services/supabase/supabase_service.dart. Every call must carry the
/// current Supabase access token as a Bearer header; this client never
/// holds a static/shared token, since a request-scoped token is the
/// whole point of Phase 3's per-request auth model (see
/// docs/architecture/10-backend-security-implementation.md).
class ApiClient {
  ApiClient._();

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      // /dashboard/summary issues a series of sequential Supabase queries
      // (one per lead status, one per active member, plus the base KPI
      // counts — see DashboardService.get_summary) rather than one
      // aggregate query; over a real network (physical device, USB
      // reverse tunnel, or plain WiFi to a remote Supabase project) that
      // can legitimately exceed 10s even though nothing is actually
      // stuck. 30s gives it room without masking a truly hung request.
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static Dio get instance => _dio;

  /// Options carrying the caller's own bearer token — pass this to
  /// every authenticated request instead of mutating shared headers.
  static Options authOptions(String accessToken) {
    return Options(headers: {'Authorization': 'Bearer $accessToken'});
  }
}
