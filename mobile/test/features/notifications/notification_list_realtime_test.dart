import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notifications/presentation/providers/notification_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import 'fake_notification_repository.dart';
import 'notification_test_container.dart';

Map<String, dynamic> _rawNotification({
  String id = 'n2',
  String type = 'system',
  String title = 'New follow-up assigned to you',
  bool isRead = false,
}) => {
  'id': id,
  'type': type,
  'title': title,
  'body': 'Acme Corp',
  'related_entity_type': 'follow_up',
  'related_entity_id': 'fu-1',
  'is_read': isRead,
  'read_at': isRead ? '2026-01-01T09:05:00+00:00' : null,
  'created_at': '2026-01-01T09:10:00+00:00',
};

void main() {
  group('NotificationListController realtime (Phase 21B)', () {
    test('a new notification is decoded straight from the payload and prepended — no repository round trip', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'n1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildNotificationTestContainer(notificationRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);
      await waitUntil(() => container.read(notificationListControllerProvider).items.length == 1);

      // Deliberately don't update the repository's return value — proves
      // the new item came from decoding the realtime payload directly,
      // not from a refetch.
      realtime.emitInsert('notifications', _rawNotification());

      await waitUntil(() => container.read(notificationListControllerProvider).items.length == 2);
      final state = container.read(notificationListControllerProvider);
      expect(state.items.first.id, 'n2');
      expect(state.total, 2);
      expect(state.unreadCount, 2);
    });

    test('a duplicate/replayed insert for an already-loaded id is ignored', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'n1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildNotificationTestContainer(notificationRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);
      await waitUntil(() => container.read(notificationListControllerProvider).items.length == 1);

      realtime.emitInsert('notifications', _rawNotification(id: 'n1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(notificationListControllerProvider).items, hasLength(1));
    });

    test('an update (e.g. read on another device) patches the item in place, preserving the rest of the page', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'n1'), testNotification(id: 'n2')]
        ..totalToReturn = 2;
      final realtime = FakeRealtimeService();
      final container = await buildNotificationTestContainer(notificationRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);
      await waitUntil(() => container.read(notificationListControllerProvider).items.length == 2);

      realtime.emitUpdate('notifications', _rawNotification(id: 'n1', isRead: true));

      await waitUntil(() => container.read(notificationListControllerProvider).unreadCount == 1);
      final state = container.read(notificationListControllerProvider);
      expect(state.items, hasLength(2));
      expect(state.items.firstWhere((n) => n.id == 'n1').isRead, isTrue);
    });

    test('a resync signal triggers a full refresh', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'n1')]
        ..totalToReturn = 1;
      final realtime = FakeRealtimeService();
      final container = await buildNotificationTestContainer(notificationRepository: repo, realtimeService: realtime);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);
      await waitUntil(() => container.read(notificationListControllerProvider).items.length == 1);

      repo
        ..itemsToReturn = [testNotification(id: 'n1'), testNotification(id: 'n2')]
        ..totalToReturn = 2;
      realtime.emitResync();

      await waitUntil(() => container.read(notificationListControllerProvider).items.length == 2);
    });
  });
}
