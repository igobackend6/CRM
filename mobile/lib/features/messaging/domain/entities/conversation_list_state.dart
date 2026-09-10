import 'conversation.dart';

enum ConversationListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Mirrors CallListState — loading/success/empty/error + pull-to-refresh
/// + offset-pagination (Phase 16 §9: paginate the conversation list,
/// don't load every conversation at once).
class ConversationListState {
  const ConversationListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.errorMessage,
  });

  const ConversationListState.initial() : this._(status: ConversationListStatus.initial);

  final ConversationListStatus status;
  final List<Conversation> items;
  final int total;
  final int limit;
  final String? errorMessage;

  bool get hasMore => items.length < total;

  ConversationListState copyWith({
    ConversationListStatus? status,
    List<Conversation>? items,
    int? total,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
