import 'activity_filter.dart';
import 'timeline_item.dart';

enum TimelineListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Mirrors FollowUpListState (Phase 7) — loading/success/empty/error +
/// offset-pagination (Phase 8 §10/§15: the timeline must be paginated,
/// never fetched all at once). Phase 15 adds [filter]: a purely local,
/// display-only narrowing of [items] (§"Activity Filters" — the backend
/// is never asked to filter by type, every source is still fetched/
/// merged as before).
class TimelineListState {
  const TimelineListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.errorMessage,
    this.filter = ActivityFilter.all,
  });

  const TimelineListState.initial() : this._(status: TimelineListStatus.initial);

  final TimelineListStatus status;
  final List<TimelineItem> items;
  final int total;
  final int limit;
  final String? errorMessage;
  final ActivityFilter filter;

  bool get hasMore => items.length < total;

  /// [items] narrowed to the active [filter] — what the UI actually
  /// renders. Pagination (`hasMore`/`loadMore`) stays based on the raw,
  /// unfiltered `items`/`total`: filtering fewer items being *visible*
  /// doesn't mean fewer exist server-side.
  List<TimelineItem> get visibleItems =>
      filter == ActivityFilter.all ? items : items.where((i) => filter.matches(i.type)).toList();

  TimelineListState copyWith({
    TimelineListStatus? status,
    List<TimelineItem>? items,
    int? total,
    String? errorMessage,
    bool clearError = false,
    ActivityFilter? filter,
  }) {
    return TimelineListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      filter: filter ?? this.filter,
    );
  }
}
