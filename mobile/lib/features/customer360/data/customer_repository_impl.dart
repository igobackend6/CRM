import '../../../services/api/customer_api_data_source.dart';
import '../../followups/domain/entities/follow_up.dart';
import '../../leads/domain/entities/lead.dart';
import '../domain/entities/timeline_item.dart';
import '../domain/entities/timeline_page.dart';
import '../domain/repositories/customer_repository.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  CustomerRepositoryImpl(this._dataSource);

  final CustomerApiDataSource _dataSource;

  @override
  Future<Lead> getCustomer({required String accessToken, required String workspaceId, required String customerId}) async {
    final json = await _dataSource.getCustomer(accessToken: accessToken, workspaceId: workspaceId, customerId: customerId);
    return Lead.fromJson(json);
  }

  @override
  Future<TimelinePage> getTimeline({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required int limit,
    required int offset,
  }) async {
    final json = await _dataSource.getTimeline(
      accessToken: accessToken,
      workspaceId: workspaceId,
      customerId: customerId,
      limit: limit,
      offset: offset,
    );
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(TimelineItem.fromJson).toList();
    return TimelinePage(items: items, total: json['total'] as int? ?? items.length, limit: json['limit'] as int? ?? limit, offset: json['offset'] as int? ?? offset);
  }

  @override
  Future<List<FollowUp>> listFollowUps({required String accessToken, required String workspaceId, required String customerId}) async {
    final list = await _dataSource.listFollowUps(accessToken: accessToken, workspaceId: workspaceId, customerId: customerId);
    return list.cast<Map<String, dynamic>>().map(FollowUp.fromJson).toList();
  }

  @override
  Future<TimelineItem> createNote({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required String text,
  }) async {
    final json = await _dataSource.createNote(accessToken: accessToken, workspaceId: workspaceId, customerId: customerId, text: text);
    // The backend returns InteractionOut (id/type/payload/actor_member/
    // created_at), not TimelineItemOut's shape — adapt it into a
    // TimelineItem here so the caller can prepend it to the timeline
    // list without a second round trip/refetch.
    final payload = (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TimelineItem.fromJson({
      'id': 'interaction:${json['id']}',
      'type': json['type'],
      'occurred_at': json['created_at'],
      'actor_member': json['actor_member'],
      'summary': (payload['text'] as String?) ?? 'Note',
      'details': payload,
    });
  }
}
