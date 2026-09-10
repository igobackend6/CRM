import '../../../services/api/rechurn_api_data_source.dart';
import '../domain/entities/rechurn_lead_card.dart';
import '../domain/entities/rechurn_page.dart';
import '../domain/repositories/rechurn_repository.dart';

class RechurnRepositoryImpl implements RechurnRepository {
  RechurnRepositoryImpl(this._dataSource);

  final RechurnApiDataSource _dataSource;

  @override
  Future<RechurnPage> getQueue({
    required String accessToken,
    required String workspaceId,
    String? segment,
    int inactiveDays = 30,
    String? assignedMemberId,
    String? priority,
    String? statusId,
    String? sourceId,
    String? search,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _dataSource.getQueue(
      accessToken: accessToken,
      workspaceId: workspaceId,
      segment: segment,
      inactiveDays: inactiveDays,
      assignedMemberId: assignedMemberId,
      priority: priority,
      statusId: statusId,
      sourceId: sourceId,
      search: search,
      limit: limit,
      offset: offset,
    );
    return RechurnPage(
      items: (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(RechurnLeadCard.fromJson).toList(),
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }
}
