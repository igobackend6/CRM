import 'app_notification.dart';

/// One page of `GET /notifications` (backend `NotificationListResponse`).
class NotificationPage {
  const NotificationPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<AppNotification> items;
  final int total;
  final int limit;
  final int offset;
}
