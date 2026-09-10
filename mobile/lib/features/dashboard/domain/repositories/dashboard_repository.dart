import '../entities/dashboard_summary.dart';
import '../entities/recent_activity_page.dart';

abstract class DashboardRepository {
  Future<DashboardSummary> getSummary({required String accessToken, required String workspaceId, String range = 'all'});

  Future<RecentActivityPage> getRecentActivity({
    required String accessToken,
    required String workspaceId,
    int limit = 10,
    int offset = 0,
  });
}
