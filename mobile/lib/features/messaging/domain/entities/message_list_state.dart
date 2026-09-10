import 'message.dart';

enum MessageListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Loading/success/empty/error + offset-pagination, plus `sending` for
/// the composer's own in-flight state (Phase 16 §"Conversation Detail":
/// "send button... disable send for empty/whitespace-only text" — the
/// screen also needs to disable it while a send is in flight, tracked
/// here rather than as separate local widget state so a failed send's
/// error message flows through the same `errorMessage` field as every
/// other list state in this codebase).
class MessageListState {
  const MessageListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 30,
    this.errorMessage,
    this.sending = false,
  });

  const MessageListState.initial() : this._(status: MessageListStatus.initial);

  final MessageListStatus status;
  final List<Message> items;
  final int total;
  final int limit;
  final String? errorMessage;
  final bool sending;

  bool get hasMore => items.length < total;

  MessageListState copyWith({
    MessageListStatus? status,
    List<Message>? items,
    int? total,
    String? errorMessage,
    bool clearError = false,
    bool? sending,
  }) {
    return MessageListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      sending: sending ?? this.sending,
    );
  }
}
