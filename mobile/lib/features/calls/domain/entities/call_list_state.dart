import 'call.dart';

enum CallListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Mirrors FollowUpListState (followups feature) — loading/success/
/// empty/error + pull-to-refresh + offset-pagination (Phase 9 §2/§15:
/// paginate the call log, don't load every call at once).
class CallListState {
  const CallListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.errorMessage,
  });

  const CallListState.initial() : this._(status: CallListStatus.initial);

  final CallListStatus status;
  final List<Call> items;
  final int total;
  final int limit;
  final String? errorMessage;

  bool get hasMore => items.length < total;

  CallListState copyWith({
    CallListStatus? status,
    List<Call>? items,
    int? total,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CallListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
