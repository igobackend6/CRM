import '../../../services/api/call_api_data_source.dart';
import '../domain/entities/call.dart';
import '../domain/entities/call_draft.dart';
import '../domain/entities/call_outcome.dart';
import '../domain/entities/call_page.dart';
import '../domain/repositories/call_repository.dart';

class CallRepositoryImpl implements CallRepository {
  CallRepositoryImpl(this._dataSource);

  final CallApiDataSource _dataSource;

  @override
  Future<CallPage> listCalls({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? direction,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _dataSource.listCalls(
      accessToken: accessToken,
      workspaceId: workspaceId,
      leadId: leadId,
      direction: direction,
      limit: limit,
      offset: offset,
    );
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(Call.fromJson).toList();
    return CallPage(
      items: items,
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }

  @override
  Future<Call> getCall({required String accessToken, required String workspaceId, required String callId}) async {
    final json = await _dataSource.getCall(accessToken: accessToken, workspaceId: workspaceId, callId: callId);
    return Call.fromJson(json);
  }

  @override
  Future<Call> createCall({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required CallDraft draft,
  }) async {
    final body = {'lead_id': leadId, ...draft.toJson()};
    final json = await _dataSource.createCall(accessToken: accessToken, workspaceId: workspaceId, body: body);
    return Call.fromJson(json);
  }

  @override
  Future<List<Call>> listLeadCalls({required String accessToken, required String workspaceId, required String leadId}) async {
    final json = await _dataSource.listLeadCalls(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return json.cast<Map<String, dynamic>>().map(Call.fromJson).toList();
  }

  @override
  Future<List<CallOutcome>> listCallOutcomes({required String accessToken, required String workspaceId}) async {
    final json = await _dataSource.listCallOutcomes(accessToken: accessToken, workspaceId: workspaceId);
    return json.cast<Map<String, dynamic>>().map(CallOutcome.fromJson).toList();
  }
}
