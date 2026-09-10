import '../entities/app_notification.dart';
import '../entities/notification_page.dart';

abstract class NotificationRepository {
  Future<NotificationPage> listNotifications({
    required String accessToken,
    required String workspaceId,
    bool? isRead,
    int limit = 20,
    int offset = 0,
  });

  Future<AppNotification> markRead({
    required String accessToken,
    required String workspaceId,
    required String notificationId,
    required bool isRead,
  });

  /// Returns how many notifications the server actually marked read —
  /// backend `POST /notifications/mark-all-read`'s `{"updated": n}`.
  Future<int> markAllRead({required String accessToken, required String workspaceId});
}
