import '../../../services/api/notification_api_data_source.dart';
import '../domain/entities/app_notification.dart';
import '../domain/entities/notification_page.dart';
import '../domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl(this._dataSource);

  final NotificationApiDataSource _dataSource;

  @override
  Future<NotificationPage> listNotifications({
    required String accessToken,
    required String workspaceId,
    bool? isRead,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _dataSource.listNotifications(
      accessToken: accessToken,
      workspaceId: workspaceId,
      isRead: isRead,
      limit: limit,
      offset: offset,
    );
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(AppNotification.fromJson).toList();
    return NotificationPage(
      items: items,
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }

  @override
  Future<AppNotification> markRead({
    required String accessToken,
    required String workspaceId,
    required String notificationId,
    required bool isRead,
  }) async {
    final json = await _dataSource.markRead(
      accessToken: accessToken,
      workspaceId: workspaceId,
      notificationId: notificationId,
      isRead: isRead,
    );
    return AppNotification.fromJson(json);
  }

  @override
  Future<int> markAllRead({required String accessToken, required String workspaceId}) async {
    final json = await _dataSource.markAllRead(accessToken: accessToken, workspaceId: workspaceId);
    return json['updated'] as int? ?? 0;
  }
}
