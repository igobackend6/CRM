import 'package:mobile/services/api/lead_api_data_source.dart';

/// Records the arguments of the last call to each method (so tests can
/// assert on what was sent — e.g. search terms, request bodies) and
/// returns whatever the test configured, or throws [errorToThrow] if set.
class FakeLeadApiDataSource implements LeadApiDataSource {
  Map<String, dynamic> listLeadsResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 20, 'offset': 0};
  Map<String, dynamic> getLeadResponse = const {};
  Map<String, dynamic> createLeadResponse = const {};
  Map<String, dynamic> updateLeadResponse = const {};
  List<dynamic> statusesResponse = const [];
  List<dynamic> sourcesResponse = const [];
  List<dynamic> tagsResponse = const [];
  Map<String, dynamic> createTagResponse = const {};
  List<dynamic> leadTagsResponse = const [];
  Map<String, dynamic> attachTagResponse = const {};
  List<dynamic> interactionsResponse = const [];
  List<dynamic> membersResponse = const [];
  Map<String, dynamic> assignLeadResponse = const {};
  List<dynamic> allocationsResponse = const [];
  Map<String, dynamic> bulkActionResponse = const {'action': 'assign', 'total': 0, 'succeeded': 0, 'failed': 0, 'results': <dynamic>[]};
  Map<String, dynamic> importLeadsResponse = const {'total': 0, 'created': 0, 'failed': 0, 'errors': <dynamic>[]};
  Map<String, dynamic> activityResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 20, 'offset': 0};
  Map<String, dynamic> createNoteResponse = const {};
  Map<String, dynamic> convertLeadResponse = const {};

  Object? errorToThrow;
  bool lastConvertCalled = false;
  String? lastNoteLeadId;
  String? lastNoteText;
  int? lastActivityOffset;

  String? lastSearch;
  int? lastOffset;
  String? lastStatusId;
  String? lastSourceId;
  String? lastFilterAssignedMemberId;
  String? lastPriority;
  bool? lastIsCustomer;
  DateTime? lastCreatedFrom;
  DateTime? lastCreatedTo;
  String? lastTagId;
  Map<String, dynamic>? lastCreateBody;
  Map<String, dynamic>? lastUpdateBody;
  bool deleteCalled = false;
  bool detachTagCalled = false;
  String? lastAssignedMemberId;
  bool lastAssignHadMemberId = false;
  List<String>? lastBulkLeadIds;
  String? lastBulkAction;
  String? lastBulkMemberId;
  String? lastBulkStatusId;
  String? lastImportCsvContent;

  void _maybeThrow() {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<Map<String, dynamic>> listLeads({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? statusId,
    String? sourceId,
    String? assignedMemberId,
    String? priority,
    bool? isCustomer,
    DateTime? createdFrom,
    DateTime? createdTo,
    String? tagId,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastSearch = search;
    lastOffset = offset;
    lastStatusId = statusId;
    lastSourceId = sourceId;
    lastFilterAssignedMemberId = assignedMemberId;
    lastPriority = priority;
    lastIsCustomer = isCustomer;
    lastCreatedFrom = createdFrom;
    lastCreatedTo = createdTo;
    lastTagId = tagId;
    return listLeadsResponse;
  }

  @override
  Future<Map<String, dynamic>> getLead({required String accessToken, required String workspaceId, required String leadId}) async {
    _maybeThrow();
    return getLeadResponse;
  }

  @override
  Future<Map<String, dynamic>> createLead({required String accessToken, required String workspaceId, required Map<String, dynamic> body}) async {
    _maybeThrow();
    lastCreateBody = body;
    return createLeadResponse;
  }

  @override
  Future<Map<String, dynamic>> updateLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required Map<String, dynamic> body,
  }) async {
    _maybeThrow();
    lastUpdateBody = body;
    return updateLeadResponse;
  }

  @override
  Future<void> deleteLead({required String accessToken, required String workspaceId, required String leadId}) async {
    _maybeThrow();
    deleteCalled = true;
  }

  @override
  Future<Map<String, dynamic>> convertLead({required String accessToken, required String workspaceId, required String leadId}) async {
    _maybeThrow();
    lastConvertCalled = true;
    return convertLeadResponse;
  }

  @override
  Future<List<dynamic>> listStatuses({required String accessToken, required String workspaceId}) async {
    _maybeThrow();
    return statusesResponse;
  }

  @override
  Future<List<dynamic>> listSources({required String accessToken, required String workspaceId}) async {
    _maybeThrow();
    return sourcesResponse;
  }

  @override
  Future<List<dynamic>> listTags({required String accessToken, required String workspaceId}) async {
    _maybeThrow();
    return tagsResponse;
  }

  @override
  Future<Map<String, dynamic>> createTag({required String accessToken, required String workspaceId, required Map<String, dynamic> body}) async {
    _maybeThrow();
    return createTagResponse;
  }

  @override
  Future<List<dynamic>> listLeadTags({required String accessToken, required String workspaceId, required String leadId}) async {
    _maybeThrow();
    return leadTagsResponse;
  }

  @override
  Future<Map<String, dynamic>> attachTag({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String tagId,
  }) async {
    _maybeThrow();
    return attachTagResponse;
  }

  @override
  Future<void> detachTag({required String accessToken, required String workspaceId, required String leadId, required String tagId}) async {
    _maybeThrow();
    detachTagCalled = true;
  }

  @override
  Future<List<dynamic>> listInteractions({required String accessToken, required String workspaceId, required String leadId}) async {
    _maybeThrow();
    return interactionsResponse;
  }

  @override
  Future<List<dynamic>> listWorkspaceMembers({required String accessToken, required String workspaceId}) async {
    _maybeThrow();
    return membersResponse;
  }

  @override
  Future<Map<String, dynamic>> assignLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    String? memberId,
  }) async {
    _maybeThrow();
    lastAssignedMemberId = memberId;
    lastAssignHadMemberId = true;
    return assignLeadResponse;
  }

  @override
  Future<List<dynamic>> listAllocations({required String accessToken, required String workspaceId, required String leadId}) async {
    _maybeThrow();
    return allocationsResponse;
  }

  @override
  Future<Map<String, dynamic>> bulkAction({
    required String accessToken,
    required String workspaceId,
    required List<String> leadIds,
    required String action,
    String? memberId,
    String? statusId,
  }) async {
    _maybeThrow();
    lastBulkLeadIds = leadIds;
    lastBulkAction = action;
    lastBulkMemberId = memberId;
    lastBulkStatusId = statusId;
    return bulkActionResponse;
  }

  @override
  Future<Map<String, dynamic>> importLeads({required String accessToken, required String workspaceId, required String csvContent}) async {
    _maybeThrow();
    lastImportCsvContent = csvContent;
    return importLeadsResponse;
  }

  @override
  Future<Map<String, dynamic>> getActivity({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastActivityOffset = offset;
    return activityResponse;
  }

  @override
  Future<Map<String, dynamic>> createNote({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String text,
  }) async {
    _maybeThrow();
    lastNoteLeadId = leadId;
    lastNoteText = text;
    return createNoteResponse;
  }
}
