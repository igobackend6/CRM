import 'follow_up.dart';

enum FollowUpListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Mirrors LeadListState (leads feature) — loading/success/empty/error +
/// pull-to-refresh + offset-pagination (Phase 7 §2A/§12: paginate the
/// global list, don't load every follow-up at once).
class FollowUpListState {
  const FollowUpListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.errorMessage,
  });

  const FollowUpListState.initial() : this._(status: FollowUpListStatus.initial);

  final FollowUpListStatus status;
  final List<FollowUp> items;
  final int total;
  final int limit;
  final String? errorMessage;

  bool get hasMore => items.length < total;

  FollowUpListState copyWith({
    FollowUpListStatus? status,
    List<FollowUp>? items,
    int? total,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FollowUpListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
