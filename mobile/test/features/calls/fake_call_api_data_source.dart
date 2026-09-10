import 'package:mobile/services/api/call_api_data_source.dart';

/// Records the arguments of the last call to each method (so tests can
/// assert on what was sent) and returns whatever the test configured, or
/// throws [errorToThrow] if set. Mirrors fake_follow_up_api_data_source.dart.
class FakeCallApiDataSource implements CallApiDataSource {
  Map<String, dynamic> listCallsResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 20, 'offset': 0};
  Map<String, dynamic> getCallResponse = const {};
  Map<String, dynamic> createCallResponse = const {};
  List<dynamic> leadCallsResponse = const [];
  List<dynamic> callOutcomesResponse = const [];

  Object? errorToThrow;

  int? lastOffset;
  String? lastLeadId;
  String? lastDirection;
  Map<String, dynamic>? lastCreateBody;

  void _maybeThrow() {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<Map<String, dynamic>> listCalls({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? direction,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastOffset = offset;
    lastLeadId = leadId;
    lastDirection = direction;
    return listCallsResponse;
  }

  @override
  Future<Map<String, dynamic>> getCall({required String accessToken, required String workspaceId, required String callId}) async {
    _maybeThrow();
    return getCallResponse;
  }

  @override
  Future<Map<String, dynamic>> createCall({
    required String accessToken,
    required String workspaceId,
    required Map<String, dynamic> body,
  }) async {
    _maybeThrow();
    lastCreateBody = body;
    return createCallResponse;
  }

  @override
  Future<List<dynamic>> listLeadCalls({required String accessToken, required String workspaceId, required String leadId}) async {
    _maybeThrow();
    lastLeadId = leadId;
    return leadCallsResponse;
  }

  @override
  Future<List<dynamic>> listCallOutcomes({required String accessToken, required String workspaceId}) async {
    _maybeThrow();
    return callOutcomesResponse;
  }
}
