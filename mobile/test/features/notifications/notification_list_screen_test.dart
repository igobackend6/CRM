import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/notifications/presentation/providers/notification_providers.dart';
import 'package:mobile/features/notifications/presentation/screens/notification_list_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_notification_repository.dart';

Future<void> _pumpNotificationListScreen(
  WidgetTester tester, {
  required FakeNotificationRepository repository,
  List<GoRoute> extraRoutes = const [],
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => const NotificationListScreen()), ...extraRoutes],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        notificationRepositoryProvider.overrideWithValue(repository),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the loaded notifications', (tester) async {
    final repo = FakeNotificationRepository()
      ..itemsToReturn = [testNotification(id: 'notif-1', title: 'Lead assigned to you')]
      ..totalToReturn = 1;

    await _pumpNotificationListScreen(tester, repository: repo);

    expect(find.text('Lead assigned to you'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no notifications', (tester) async {
    final repo = FakeNotificationRepository();

    await _pumpNotificationListScreen(tester, repository: repo);

    expect(find.text('No notifications yet.'), findsOneWidget);
  });

  testWidgets('shows an error state with retry on failure', (tester) async {
    final repo = FakeNotificationRepository()..listError = const NetworkException('Could not reach the server.');

    await _pumpNotificationListScreen(tester, repository: repo);

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping a notification with a resolvable target marks it read and navigates', (tester) async {
    final repo = FakeNotificationRepository()
      ..itemsToReturn = [testNotification(id: 'notif-1', title: 'Lead assigned to you', relatedEntityType: 'lead', relatedEntityId: 'lead-1')]
      ..totalToReturn = 1;

    await _pumpNotificationListScreen(
      tester,
      repository: repo,
      extraRoutes: [
        GoRoute(path: '/app/leads/lead-1', builder: (context, state) => const Scaffold(body: Text('LEAD_DETAIL_MARKER'))),
      ],
    );

    await tester.tap(find.text('Lead assigned to you'));
    await tester.pumpAndSettle();

    expect(find.text('LEAD_DETAIL_MARKER'), findsOneWidget);
    expect(repo.lastMarkReadId, 'notif-1');
    expect(repo.lastMarkReadValue, true);
  });

  testWidgets('tapping a notification with no resolvable target only marks it read', (tester) async {
    final repo = FakeNotificationRepository()
      ..itemsToReturn = [
        testNotification(id: 'notif-1', type: 'system', title: 'Workspace update', relatedEntityType: null, relatedEntityId: null),
      ]
      ..totalToReturn = 1;

    await _pumpNotificationListScreen(tester, repository: repo);

    await tester.tap(find.text('Workspace update'));
    await tester.pumpAndSettle();

    // Still on the notification list — nothing to navigate to.
    expect(find.text('Workspace update'), findsOneWidget);
    expect(repo.lastMarkReadId, 'notif-1');
  });

  testWidgets('an already-read notification tap does not call markRead again', (tester) async {
    final repo = FakeNotificationRepository()
      ..itemsToReturn = [testNotification(id: 'notif-1', title: 'Already read', isRead: true, relatedEntityType: null, relatedEntityId: null)]
      ..totalToReturn = 1;

    await _pumpNotificationListScreen(tester, repository: repo);

    await tester.tap(find.text('Already read'));
    await tester.pumpAndSettle();

    expect(repo.lastMarkReadId, isNull);
  });

  testWidgets('"Mark all read" only appears when there is something unread', (tester) async {
    final repo = FakeNotificationRepository()
      ..itemsToReturn = [testNotification(id: 'notif-1', isRead: true)]
      ..totalToReturn = 1;

    await _pumpNotificationListScreen(tester, repository: repo);

    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('"Mark all read" appears and clears the unread dot when tapped', (tester) async {
    final repo = FakeNotificationRepository()
      ..itemsToReturn = [testNotification(id: 'notif-1', isRead: false)]
      ..totalToReturn = 1
      ..markAllReadReturns = 1;

    await _pumpNotificationListScreen(tester, repository: repo);
    expect(find.text('Mark all read'), findsOneWidget);

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    expect(repo.markAllReadCallCount, 1);
    expect(find.text('Mark all read'), findsNothing);
  });
}
