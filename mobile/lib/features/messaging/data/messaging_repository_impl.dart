import '../../../services/api/messaging_api_data_source.dart';
import '../domain/entities/conversation.dart';
import '../domain/entities/conversation_page.dart';
import '../domain/entities/message.dart';
import '../domain/entities/message_page.dart';
import '../domain/repositories/messaging_repository.dart';

class MessagingRepositoryImpl implements MessagingRepository {
  MessagingRepositoryImpl(this._dataSource);

  final MessagingApiDataSource _dataSource;

  @override
  Future<ConversationPage> listConversations({
    required String accessToken,
    required String workspaceId,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _dataSource.listConversations(accessToken: accessToken, workspaceId: workspaceId, limit: limit, offset: offset);
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(Conversation.fromJson).toList();
    return ConversationPage(
      items: items,
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }

  @override
  Future<Conversation> getOrCreateConversation({
    required String accessToken,
    required String workspaceId,
    required String leadId,
  }) async {
    final json = await _dataSource.getOrCreateConversation(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return Conversation.fromJson(json);
  }

  @override
  Future<MessagePage> listMessages({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    int limit = 30,
    int offset = 0,
  }) async {
    final json = await _dataSource.listMessages(
      accessToken: accessToken,
      workspaceId: workspaceId,
      conversationId: conversationId,
      limit: limit,
      offset: offset,
    );
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(Message.fromJson).toList();
    return MessagePage(
      items: items,
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }

  @override
  Future<Message> sendMessage({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required String body,
  }) async {
    final json = await _dataSource.sendMessage(accessToken: accessToken, workspaceId: workspaceId, conversationId: conversationId, body: body);
    return Message.fromJson(json);
  }

  @override
  Future<void> markConversationRead({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
  }) {
    return _dataSource.markConversationRead(accessToken: accessToken, workspaceId: workspaceId, conversationId: conversationId);
  }
}
