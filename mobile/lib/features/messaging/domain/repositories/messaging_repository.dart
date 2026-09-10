import '../entities/conversation.dart';
import '../entities/conversation_page.dart';
import '../entities/message.dart';
import '../entities/message_page.dart';

abstract class MessagingRepository {
  Future<ConversationPage> listConversations({
    required String accessToken,
    required String workspaceId,
    int limit = 20,
    int offset = 0,
  });

  /// Get-or-create the lead's single conversation (§"Lead conversation").
  Future<Conversation> getOrCreateConversation({
    required String accessToken,
    required String workspaceId,
    required String leadId,
  });

  Future<MessagePage> listMessages({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    int limit = 30,
    int offset = 0,
  });

  Future<Message> sendMessage({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
    required String body,
  });

  Future<void> markConversationRead({
    required String accessToken,
    required String workspaceId,
    required String conversationId,
  });
}
