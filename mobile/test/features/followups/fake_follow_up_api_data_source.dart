import 'package:mobile/services/api/follow_up_api_data_source.dart';

/// Records the arguments of the last call to each method (so tests can
/// assert on what was sent) and returns whatever the test configured, or
/// throws [errorToThrow] if set. Mirrors fake_lead_api_data_source.dart.
class FakeFollowUpApiDataSource implements FollowUpApiDataSource {
  Map<String, dynamic> listFollowUpsResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 20, 'offset': 0};
  Map<String, dynamic> getFollowUpResponse = const {};
  Map<String, dynamic> createFollowUpResponse = const {};
  Map<String, dynamic> updateFollowUpResponse = const {};
  List<dynamic> leadFollowUpsResponse = const [];

  Object? errorToThrow;

  int? lastOffset;
  String? lastLeadId;
  String? lastStatus;
  Map<String, dynamic>? lastCreateBody;
  Map<String, dynamic>? lastUpdateBody;
  String? lastUpdateFollowUpId;

  void _maybeThrow() {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<Map<String, dynamic>> listFollowUps({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? status,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastOffset = offset;
    lastLeadId = leadId;
    lastStatus = status;
    return listFollowUpsResponse;
  }

  @override
  Future<Map<String, dynamic>> getFollowUp({required String accessToken, required String workspaceId, required String followUpId}) async {
    _maybeThrow();
    return getFollowUpResponse;
  }

  @override
  Future<Map<String, dynamic>> createFollowUp({
    required String accessToken,
    required String workspaceId,
    required Map<String, dynamic> body,
  }) async {
    _maybeThrow();
    lastCreateBody = body;
    return createFollowUpResponse;
  }

  @override
  Future<Map<String, dynamic>> updateFollowUp({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required Map<String, dynamic> body,
  }) async {
    _maybeThrow();
    lastUpdateFollowUpId = followUpId;
    lastUpdateBody = body;
    return updateFollowUpResponse;
  }

  @override
  Future<List<dynamic>> listLeadFollowUps({required String accessToken, required String workspaceId, required String leadId}) async {
    _maybeThrow();
    lastLeadId = leadId;
    return leadFollowUpsResponse;
  }
}
