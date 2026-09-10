import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/notifications/domain/entities/notification_list_state.dart';
import 'package:mobile/features/notifications/presentation/providers/notification_providers.dart';

import '../../helpers/wait_until.dart';
import 'fake_notification_repository.dart';
import 'notification_test_container.dart';

void main() {
  group('NotificationListController', () {
    test('loads notifications on workspace selection', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'notif-1')]
        ..totalToReturn = 1;
      final container = await buildNotificationTestContainer(notificationRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);

      await waitUntil(() => container.read(notificationListControllerProvider).status == NotificationListStatus.success);

      expect(container.read(notificationListControllerProvider).items.map((n) => n.id), ['notif-1']);
    });

    test('an empty result lands in the empty state', () async {
      final repo = FakeNotificationRepository();
      final container = await buildNotificationTestContainer(notificationRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);

      await waitUntil(() => container.read(notificationListControllerProvider).status == NotificationListStatus.empty);
    });

    test('a failure lands in the error state with its message', () async {
      final repo = FakeNotificationRepository()..listError = const NetworkException('Could not reach the server.');
      final container = await buildNotificationTestContainer(notificationRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);

      await waitUntil(() => container.read(notificationListControllerProvider).status == NotificationListStatus.error);
      expect(container.read(notificationListControllerProvider).errorMessage, 'Could not reach the server.');
    });

    test('loadMore appends the next page', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'notif-1')]
        ..totalToReturn = 2;
      final container = await buildNotificationTestContainer(notificationRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);
      await waitUntil(() => container.read(notificationListControllerProvider).status == NotificationListStatus.success);

      repo.itemsToReturn = [testNotification(id: 'notif-2')];
      await container.read(notificationListControllerProvider.notifier).loadMore();

      expect(repo.lastOffset, 1);
      expect(container.read(notificationListControllerProvider).items.map((n) => n.id), ['notif-1', 'notif-2']);
    });

    test('setRead marks one notification read in place without a full refresh', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'notif-1', isRead: false)]
        ..totalToReturn = 1;
      final container = await buildNotificationTestContainer(notificationRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);
      await waitUntil(() => container.read(notificationListControllerProvider).status == NotificationListStatus.success);

      await container.read(notificationListControllerProvider.notifier).setRead('notif-1', true);

      expect(repo.lastMarkReadId, 'notif-1');
      expect(repo.lastMarkReadValue, true);
      expect(container.read(notificationListControllerProvider).items.single.isRead, true);
    });

    test('markAllRead marks every currently-loaded item read', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'notif-1', isRead: false), testNotification(id: 'notif-2', isRead: false)]
        ..totalToReturn = 2
        ..markAllReadReturns = 2;
      final container = await buildNotificationTestContainer(notificationRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);
      await waitUntil(() => container.read(notificationListControllerProvider).status == NotificationListStatus.success);

      await container.read(notificationListControllerProvider.notifier).markAllRead();

      expect(repo.markAllReadCallCount, 1);
      expect(container.read(notificationListControllerProvider).items.every((n) => n.isRead), true);
    });

    test('unreadCount reflects only the currently-loaded unread items', () async {
      final repo = FakeNotificationRepository()
        ..itemsToReturn = [testNotification(id: 'notif-1', isRead: false), testNotification(id: 'notif-2', isRead: true)]
        ..totalToReturn = 2;
      final container = await buildNotificationTestContainer(notificationRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, notificationListControllerProvider).close);
      await waitUntil(() => container.read(notificationListControllerProvider).status == NotificationListStatus.success);

      expect(container.read(notificationListControllerProvider).unreadCount, 1);
    });
  });
}
