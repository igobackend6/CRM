import 'conversation.dart';

/// One page of `GET /conversations` (backend `ConversationListResponse`).
class ConversationPage {
  const ConversationPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<Conversation> items;
  final int total;
  final int limit;
  final int offset;
}
