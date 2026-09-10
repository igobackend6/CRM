import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/notifications/data/notification_repository_impl.dart';

import 'fake_notification_api_data_source.dart';

Map<String, dynamic> _notificationJson({
  String id = 'notif-1',
  String type = 'lead_assigned',
  bool isRead = false,
  String? relatedEntityType = 'lead',
  String? relatedEntityId = 'lead-1',
}) =>
    {
      'id': id,
      'type': type,
      'title': 'Lead assigned to you',
      'body': 'Acme Corp',
      'related_entity_type': relatedEntityType,
      'related_entity_id': relatedEntityId,
      'is_read': isRead,
      'read_at': isRead ? '2026-01-01T09:05:00Z' : null,
      'created_at': '2026-01-01T09:00:00Z',
    };

void main() {
  group('NotificationRepositoryImpl', () {
    test('listNotifications maps items and total', () async {
      final dataSource = FakeNotificationApiDataSource()
        ..listNotificationsResponse = {
          'items': [_notificationJson()],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = NotificationRepositoryImpl(dataSource);

      final page = await repo.listNotifications(accessToken: 't', workspaceId: 'w1');

      expect(page.items, hasLength(1));
      expect(page.items.first.title, 'Lead assigned to you');
      expect(page.total, 1);
    });

    test('listNotifications forwards the unread filter', () async {
      final dataSource = FakeNotificationApiDataSource();
      final repo = NotificationRepositoryImpl(dataSource);

      await repo.listNotifications(accessToken: 't', workspaceId: 'w1', isRead: false);

      expect(dataSource.lastIsRead, false);
    });

    test('markRead maps the updated notification', () async {
      final dataSource = FakeNotificationApiDataSource()..markReadResponse = _notificationJson(isRead: true);
      final repo = NotificationRepositoryImpl(dataSource);

      final updated = await repo.markRead(accessToken: 't', workspaceId: 'w1', notificationId: 'notif-1', isRead: true);

      expect(updated.isRead, true);
      expect(dataSource.lastMarkReadId, 'notif-1');
      expect(dataSource.lastMarkReadValue, true);
    });

    test('markAllRead returns the updated count', () async {
      final dataSource = FakeNotificationApiDataSource()..markAllReadResponse = {'updated': 3};
      final repo = NotificationRepositoryImpl(dataSource);

      final count = await repo.markAllRead(accessToken: 't', workspaceId: 'w1');

      expect(count, 3);
    });

    test('a notification with no related entity maps relatedEntityType/Id to null', () async {
      final dataSource = FakeNotificationApiDataSource()
        ..listNotificationsResponse = {
          'items': [_notificationJson(type: 'system', relatedEntityType: null, relatedEntityId: null)],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = NotificationRepositoryImpl(dataSource);

      final page = await repo.listNotifications(accessToken: 't', workspaceId: 'w1');

      expect(page.items.first.relatedEntityType, isNull);
      expect(page.items.first.relatedEntityId, isNull);
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeNotificationApiDataSource()..errorToThrow = const NotFoundException('Notification not found.');
      final repo = NotificationRepositoryImpl(dataSource);

      expect(
        () => repo.markRead(accessToken: 't', workspaceId: 'w1', notificationId: 'missing', isRead: true),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
