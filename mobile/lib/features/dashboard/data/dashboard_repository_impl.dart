import '../../../services/api/dashboard_api_data_source.dart';
import '../domain/entities/dashboard_summary.dart';
import '../domain/entities/recent_activity_item.dart';
import '../domain/entities/recent_activity_page.dart';
import '../domain/repositories/dashboard_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl(this._dataSource);

  final DashboardApiDataSource _dataSource;

  @override
  Future<DashboardSummary> getSummary({required String accessToken, required String workspaceId, String range = 'all'}) async {
    final json = await _dataSource.getSummary(accessToken: accessToken, workspaceId: workspaceId, range: range);
    return DashboardSummary.fromJson(json);
  }

  @override
  Future<RecentActivityPage> getRecentActivity({
    required String accessToken,
    required String workspaceId,
    int limit = 10,
    int offset = 0,
  }) async {
    final json = await _dataSource.getRecentActivity(accessToken: accessToken, workspaceId: workspaceId, limit: limit, offset: offset);
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(RecentActivityItem.fromJson).toList();
    return RecentActivityPage(
      items: items,
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }
}
