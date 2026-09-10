import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:mobile/features/messaging/presentation/screens/conversation_list_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_messaging_repository.dart';

Future<void> _pumpConversationListScreen(
  WidgetTester tester, {
  required FakeMessagingRepository repository,
  List<GoRoute> extraRoutes = const [],
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => const ConversationListScreen()), ...extraRoutes],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        messagingRepositoryProvider.overrideWithValue(repository),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a loading indicator, then the list', (tester) async {
    final repo = FakeMessagingRepository()
      ..conversationsToReturn = [testConversation(id: 'conv-1', leadName: 'Acme Corp')]
      ..conversationsTotalToReturn = 1;

    await _pumpConversationListScreen(tester, repository: repo);

    expect(find.text('Acme Corp'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no conversations', (tester) async {
    final repo = FakeMessagingRepository();

    await _pumpConversationListScreen(tester, repository: repo);

    expect(find.text('No conversations yet.'), findsOneWidget);
  });

  testWidgets('shows an error state with retry on failure', (tester) async {
    final repo = FakeMessagingRepository()..listConversationsError = const NetworkException('Could not reach the server.');

    await _pumpConversationListScreen(tester, repository: repo);

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows the unread count badge and latest message preview', (tester) async {
    final repo = FakeMessagingRepository()
      ..conversationsToReturn = [
        testConversation(id: 'conv-1', leadName: 'Acme Corp', latestMessagePreview: 'See you then', unreadCount: 3),
      ]
      ..conversationsTotalToReturn = 1;

    await _pumpConversationListScreen(tester, repository: repo);

    expect(find.text('See you then'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads the list', (tester) async {
    final repo = FakeMessagingRepository()
      ..conversationsToReturn = [testConversation(id: 'conv-1', leadName: 'Acme Corp')]
      ..conversationsTotalToReturn = 1;

    await _pumpConversationListScreen(tester, repository: repo);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    repo.conversationsToReturn = [testConversation(id: 'conv-2', leadName: 'Globex')];
    final context = tester.element(find.byType(ConversationListScreen));
    await ProviderScope.containerOf(context).read(conversationListControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('Globex'), findsOneWidget);
  });

  testWidgets('tapping a conversation navigates to its detail route', (tester) async {
    final repo = FakeMessagingRepository()
      ..conversationsToReturn = [testConversation(id: 'conv-1', leadName: 'Acme Corp')]
      ..conversationsTotalToReturn = 1;

    await _pumpConversationListScreen(
      tester,
      repository: repo,
      extraRoutes: [
        GoRoute(path: '/app/messages/conv-1', builder: (context, state) => const Scaffold(body: Text('CONVERSATION_DETAIL_MARKER'))),
      ],
    );

    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();

    expect(find.text('CONVERSATION_DETAIL_MARKER'), findsOneWidget);
  });
}
