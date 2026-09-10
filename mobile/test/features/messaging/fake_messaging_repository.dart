import 'package:mobile/features/followups/domain/entities/lead_summary.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/messaging/domain/entities/conversation.dart';
import 'package:mobile/features/messaging/domain/entities/conversation_page.dart';
import 'package:mobile/features/messaging/domain/entities/message.dart';
import 'package:mobile/features/messaging/domain/entities/message_page.dart';
import 'package:mobile/features/messaging/domain/repositories/messaging_repository.dart';

Conversation testConversation({
  String id = 'conv-1',
  String leadId = 'l1',
  String leadName = 'Acme Corp',
  String? latestMessagePreview,
  DateTime? latestMessageAt,
  int unreadCount = 0,
}) =>
    Conversation(
      id: id,
      workspaceId: 'w1',
      lead: LeadSummary(id: leadId, name: leadName),
      latestMessagePreview: latestMessagePreview,
      latestMessageAt: latestMessageAt,
      unreadCount: unreadCount,
      createdAt: DateTime.utc(2026, 1, 1, 9, 0),
      updatedAt: DateTime.utc(2026, 1, 1, 9, 0),
    );

Message testMessage({
  String id = 'msg-1',
  String conversationId = 'conv-1',
  MemberSummary? senderMember,
  String body = 'Hello there',
  DateTime? createdAt,
  DateTime? readAt,
}) =>
    Message(
      id: id,
      workspaceId: 'w1',
      conversationId: conversationId,
      senderMember: senderMember ?? const MemberSummary(id: 'm1', fullName: 'Agent One'),
      body: body,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1, 9, 0),
      readAt: readAt,
    );

class FakeMessagingRepository implements MessagingRepository {
  List<Conversation> conversationsToReturn = const [];
  int conversationsTotalToReturn = 0;
  Object? listConversationsError;

  Conversation? conversationToReturn;
  Object? getOrCreateError;
  String? lastGetOrCreateLeadId;

  List<Message> messagesToReturn = const [];
  int messagesTotalToReturn = 0;
  Object? listMessagesError;

  Message? sendMessageResult;
  Object? sendMessageError;
  String? lastSentBody;
  String? lastSentConversationId;

  Object? markReadError;
  String? lastMarkReadConversationId;
  int markReadCallCount = 0;

  int? lastConversationsOffset;
  int? lastMessagesOffset;

  @override
  Future<ConversationPage> listConversations({
    required String accessToken,
    required String workspaceId,
    int limit = 20,
    int offset = 0,
  }) async {
    if (listConversationsError != null) throw listConversationsError!;
    lastConversationsOffset = offset;
    return ConversationPage(items: conversationsToReturn, total: conversationsTotalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<Conversation> getOrCreateConversation({
    required String accessToken,
    required String workspaceId,
    required String leadId,
  }) async {
    if (getOrCreateError != null) throw getOrCreateError!;
    lastGetOrCreateLeadId = leadId;
    return conversationToReturn ?? testConversation(leadId: leadId);
  }

  @override
  Future<MessagePage> listMessages({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    int limit = 30,
    int offset = 0,
  }) async {
    if (listMessagesError != null) throw listMessagesError!;
    lastMessagesOffset = offset;
    return MessagePage(items: messagesToReturn, total: messagesTotalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<Message> sendMessage({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required String body,
  }) async {
    if (sendMessageError != null) throw sendMessageError!;
    lastSentBody = body;
    lastSentConversationId = conversationId;
    return sendMessageResult ?? testMessage(conversationId: conversationId, body: body);
  }

  @override
  Future<void> markConversationRead({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
  }) async {
    markReadCallCount++;
    lastMarkReadConversationId = conversationId;
    if (markReadError != null) throw markReadError!;
  }
}
