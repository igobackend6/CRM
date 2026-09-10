import '../../../services/api/follow_up_api_data_source.dart';
import '../domain/entities/follow_up.dart';
import '../domain/entities/follow_up_draft.dart';
import '../domain/entities/follow_up_page.dart';
import '../domain/repositories/follow_up_repository.dart';

class FollowUpRepositoryImpl implements FollowUpRepository {
  FollowUpRepositoryImpl(this._dataSource);

  final FollowUpApiDataSource _dataSource;

  @override
  Future<FollowUpPage> listFollowUps({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _dataSource.listFollowUps(
      accessToken: accessToken,
      workspaceId: workspaceId,
      leadId: leadId,
      status: status,
      limit: limit,
      offset: offset,
    );
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(FollowUp.fromJson).toList();
    return FollowUpPage(
      items: items,
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }

  @override
  Future<FollowUp> getFollowUp({required String accessToken, required String workspaceId, required String followUpId}) async {
    final json = await _dataSource.getFollowUp(accessToken: accessToken, workspaceId: workspaceId, followUpId: followUpId);
    return FollowUp.fromJson(json);
  }

  @override
  Future<FollowUp> createFollowUp({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required FollowUpDraft draft,
  }) async {
    final body = {'lead_id': leadId, ...draft.toJson()};
    final json = await _dataSource.createFollowUp(accessToken: accessToken, workspaceId: workspaceId, body: body);
    return FollowUp.fromJson(json);
  }

  @override
  Future<FollowUp> updateFollowUp({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required FollowUpDraft draft,
  }) async {
    final json = await _dataSource.updateFollowUp(
      accessToken: accessToken,
      workspaceId: workspaceId,
      followUpId: followUpId,
      body: draft.toJson(),
    );
    return FollowUp.fromJson(json);
  }

  @override
  Future<FollowUp> updateFollowUpStatus({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required String status,
  }) async {
    final json = await _dataSource.updateFollowUp(
      accessToken: accessToken,
      workspaceId: workspaceId,
      followUpId: followUpId,
      body: {'status': status},
    );
    return FollowUp.fromJson(json);
  }

  @override
  Future<List<FollowUp>> listLeadFollowUps({required String accessToken, required String workspaceId, required String leadId}) async {
    final json = await _dataSource.listLeadFollowUps(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return json.cast<Map<String, dynamic>>().map(FollowUp.fromJson).toList();
  }
}
