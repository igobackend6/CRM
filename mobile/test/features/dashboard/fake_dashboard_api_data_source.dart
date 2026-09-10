import 'package:mobile/services/api/dashboard_api_data_source.dart';

class FakeDashboardApiDataSource implements DashboardApiDataSource {
  Map<String, dynamic> summaryResponse = const {};
  Map<String, dynamic> recentActivityResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 10, 'offset': 0};
  Object? errorToThrow;

  int? lastLimit;
  int? lastOffset;
  String? lastRange;

  void _maybeThrow() {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<Map<String, dynamic>> getSummary({required String accessToken, required String workspaceId, String range = 'all'}) async {
    _maybeThrow();
    lastRange = range;
    return summaryResponse;
  }

  @override
  Future<Map<String, dynamic>> getRecentActivity({
    required String accessToken,
    required String workspaceId,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastLimit = limit;
    lastOffset = offset;
    return recentActivityResponse;
  }
}
