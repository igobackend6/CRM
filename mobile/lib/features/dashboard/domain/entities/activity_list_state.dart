import 'recent_activity_item.dart';

enum ActivityListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Mirrors CallListState/NotificationListState — loading/success/empty/
/// error + pull-to-refresh + offset-pagination, for the dashboard's
/// recent-activity feed specifically (the KPI cards and follow-up/call
/// preview sections are each their own independent `FutureProvider`,
/// not part of this state — see dashboard_providers.dart).
class ActivityListState {
  const ActivityListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 10,
    this.errorMessage,
  });

  const ActivityListState.initial() : this._(status: ActivityListStatus.initial);

  final ActivityListStatus status;
  final List<RecentActivityItem> items;
  final int total;
  final int limit;
  final String? errorMessage;

  bool get hasMore => items.length < total;

  ActivityListState copyWith({
    ActivityListStatus? status,
    List<RecentActivityItem>? items,
    int? total,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ActivityListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
