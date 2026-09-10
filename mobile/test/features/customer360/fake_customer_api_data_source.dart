import 'package:mobile/services/api/customer_api_data_source.dart';

class FakeCustomerApiDataSource implements CustomerApiDataSource {
  Map<String, dynamic> getCustomerResponse = const {};
  Map<String, dynamic> getTimelineResponse = const {};
  List<dynamic> listFollowUpsResponse = const [];
  Map<String, dynamic> createNoteResponse = const {};

  Object? errorToThrow;

  String? lastCustomerId;
  int? lastTimelineOffset;
  String? lastNoteText;

  @override
  Future<Map<String, dynamic>> getCustomer({required String accessToken, required String workspaceId, required String customerId}) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastCustomerId = customerId;
    return getCustomerResponse;
  }

  @override
  Future<Map<String, dynamic>> getTimeline({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required int limit,
    required int offset,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastTimelineOffset = offset;
    return getTimelineResponse;
  }

  @override
  Future<List<dynamic>> listFollowUps({required String accessToken, required String workspaceId, required String customerId}) async {
    if (errorToThrow != null) throw errorToThrow!;
    return listFollowUpsResponse;
  }

  @override
  Future<Map<String, dynamic>> createNote({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required String text,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastNoteText = text;
    return createNoteResponse;
  }
}
