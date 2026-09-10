import 'package:mobile/features/notifications/domain/entities/app_notification.dart';
import 'package:mobile/features/notifications/domain/entities/notification_page.dart';
import 'package:mobile/features/notifications/domain/repositories/notification_repository.dart';

AppNotification testNotification({
  String id = 'notif-1',
  String type = 'lead_assigned',
  String title = 'Lead assigned to you',
  String? body = 'Acme Corp',
  String? relatedEntityType = 'lead',
  String? relatedEntityId = 'lead-1',
  bool isRead = false,
  DateTime? createdAt,
}) =>
    AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      relatedEntityType: relatedEntityType,
      relatedEntityId: relatedEntityId,
      isRead: isRead,
      readAt: isRead ? DateTime.utc(2026, 1, 1, 9, 5) : null,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1, 9, 0),
    );

class FakeNotificationRepository implements NotificationRepository {
  List<AppNotification> itemsToReturn = [];
  int totalToReturn = 0;
  Object? listError;
  AppNotification? markReadReturns;
  Object? markReadError;
  int markAllReadReturns = 0;
  Object? markAllReadError;

  int? lastOffset;
  bool? lastIsReadFilter;
  String? lastMarkReadId;
  bool? lastMarkReadValue;
  int markAllReadCallCount = 0;

  @override
  Future<NotificationPage> listNotifications({
    required String accessToken,
    required String workspaceId,
    bool? isRead,
    int limit = 20,
    int offset = 0,
  }) async {
    if (listError != null) throw listError!;
    lastOffset = offset;
    lastIsReadFilter = isRead;
    return NotificationPage(items: itemsToReturn, total: totalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<AppNotification> markRead({
    required String accessToken,
    required String workspaceId,
    required String notificationId,
    required bool isRead,
  }) async {
    if (markReadError != null) throw markReadError!;
    lastMarkReadId = notificationId;
    lastMarkReadValue = isRead;
    if (markReadReturns != null) return markReadReturns!;
    // Mirrors the real backend: marking read only ever changes
    // is_read/read_at (the `prevent_notification_content_edit` trigger
    // rejects everything else), so the default fallback preserves
    // whatever the test already put in itemsToReturn rather than
    // reverting title/type/relatedEntity to testNotification()'s
    // defaults.
    final existing = itemsToReturn.where((n) => n.id == notificationId);
    if (existing.isNotEmpty) return existing.first.copyWith(isRead: isRead);
    return testNotification(id: notificationId, isRead: isRead);
  }

  @override
  Future<int> markAllRead({required String accessToken, required String workspaceId}) async {
    if (markAllReadError != null) throw markAllReadError!;
    markAllReadCallCount++;
    return markAllReadReturns;
  }
}
