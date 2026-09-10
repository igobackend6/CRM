import 'package:mobile/services/api/rechurn_api_data_source.dart';

class FakeRechurnApiDataSource implements RechurnApiDataSource {
  Map<String, dynamic> queueResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 20, 'offset': 0};
  Object? errorToThrow;

  String? lastSegment;
  int? lastInactiveDays;
  String? lastAssignedMemberId;
  String? lastPriority;
  String? lastStatusId;
  String? lastSourceId;
  String? lastSearch;
  int? lastOffset;

  @override
  Future<Map<String, dynamic>> getQueue({
    required String accessToken,
    required String workspaceId,
    String? segment,
    int inactiveDays = 30,
    String? assignedMemberId,
    String? priority,
    String? statusId,
    String? sourceId,
    String? search,
    required int limit,
    required int offset,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastSegment = segment;
    lastInactiveDays = inactiveDays;
    lastAssignedMemberId = assignedMemberId;
    lastPriority = priority;
    lastStatusId = statusId;
    lastSourceId = sourceId;
    lastSearch = search;
    lastOffset = offset;
    return queueResponse;
  }
}
