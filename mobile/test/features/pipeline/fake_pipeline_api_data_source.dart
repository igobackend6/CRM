import 'package:mobile/services/api/pipeline_api_data_source.dart';

class FakePipelineApiDataSource implements PipelineApiDataSource {
  Map<String, dynamic> pipelineResponse = const {'columns': <dynamic>[], 'limit': 50, 'offset': 0};
  Map<String, dynamic> changeStatusResponse = const {};
  Object? errorToThrow;

  String? lastSearch;
  String? lastAssignedMemberId;
  String? lastSourceId;
  String? lastLeadId;
  String? lastStatusId;

  void _maybeThrow() {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<Map<String, dynamic>> getPipeline({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? assignedMemberId,
    String? sourceId,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastSearch = search;
    lastAssignedMemberId = assignedMemberId;
    lastSourceId = sourceId;
    return pipelineResponse;
  }

  @override
  Future<Map<String, dynamic>> changeLeadStatus({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String statusId,
  }) async {
    _maybeThrow();
    lastLeadId = leadId;
    lastStatusId = statusId;
    return changeStatusResponse;
  }
}
