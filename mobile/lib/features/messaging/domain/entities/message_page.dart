import 'message.dart';

/// One page of `GET /conversations/{id}/messages` (backend
/// `MessageListResponse`). Oldest-first (see MessageRepository's
/// `list_for_conversation` docstring on the backend).
class MessagePage {
  const MessagePage({required this.items, required this.total, required this.limit, required this.offset});

  final List<Message> items;
  final int total;
  final int limit;
  final int offset;
}
