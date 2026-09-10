import 'package:mobile/services/api/messaging_api_data_source.dart';

/// Mirrors fake_call_api_data_source.dart.
class FakeMessagingApiDataSource implements MessagingApiDataSource {
  Map<String, dynamic> listConversationsResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 20, 'offset': 0};
  Map<String, dynamic> getOrCreateConversationResponse = const {};
  Map<String, dynamic> listMessagesResponse = const {'items': <dynamic>[], 'total': 0, 'limit': 30, 'offset': 0};
  Map<String, dynamic> sendMessageResponse = const {};

  Object? errorToThrow;

  int? lastOffset;
  String? lastLeadId;
  String? lastConversationId;
  String? lastSentBody;
  bool markReadCalled = false;

  void _maybeThrow() {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<Map<String, dynamic>> listConversations({
    required String accessToken,
    required String workspaceId,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastOffset = offset;
    return listConversationsResponse;
  }

  @override
  Future<Map<String, dynamic>> getOrCreateConversation({
    required String accessToken,
    required String workspaceId,
    required String leadId,
  }) async {
    _maybeThrow();
    lastLeadId = leadId;
    return getOrCreateConversationResponse;
  }

  @override
  Future<Map<String, dynamic>> listMessages({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required int limit,
    required int offset,
  }) async {
    _maybeThrow();
    lastConversationId = conversationId;
    lastOffset = offset;
    return listMessagesResponse;
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required String body,
  }) async {
    _maybeThrow();
    lastConversationId = conversationId;
    lastSentBody = body;
    return sendMessageResponse;
  }

  @override
  Future<void> markConversationRead({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
  }) async {
    _maybeThrow();
    markReadCalled = true;
    lastConversationId = conversationId;
  }
}
