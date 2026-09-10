import 'app_notification.dart';

enum NotificationListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Mirrors CallListState (calls feature) — loading/success/empty/error +
/// pull-to-refresh + offset-pagination (Phase 10 §3: paginate the
/// notification list, don't load every notification at once).
class NotificationListState {
  const NotificationListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.errorMessage,
  });

  const NotificationListState.initial() : this._(status: NotificationListStatus.initial);

  final NotificationListStatus status;
  final List<AppNotification> items;
  final int total;
  final int limit;
  final String? errorMessage;

  bool get hasMore => items.length < total;

  int get unreadCount => items.where((n) => !n.isRead).length;

  NotificationListState copyWith({
    NotificationListStatus? status,
    List<AppNotification>? items,
    int? total,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotificationListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Replaces one item in place (after mark read/unread) without a full
  /// refresh — keeps scroll position and the rest of the loaded page
  /// intact.
  NotificationListState replaceItem(AppNotification updated) {
    return copyWith(items: [for (final item in items) if (item.id == updated.id) updated else item]);
  }

  /// Marks every currently-loaded item read (after "mark all read") —
  /// paired with the count the server actually updated, which may cover
  /// unread items beyond this page too.
  NotificationListState markAllLoadedRead() {
    return copyWith(items: [for (final item in items) item.isRead ? item : item.copyWith(isRead: true, readAt: DateTime.now())]);
  }
}
