import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:mobile/features/messaging/presentation/screens/conversation_detail_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_messaging_repository.dart';

Future<void> _pumpConversationDetailScreen(
  WidgetTester tester, {
  required FakeMessagingRepository repository,
  String conversationId = 'conv-1',
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => ConversationDetailScreen(conversationId: conversationId))],
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
  testWidgets('renders message history with sender and body', (tester) async {
    final repo = FakeMessagingRepository()
      ..messagesToReturn = [
        testMessage(id: 'msg-1', senderMember: const MemberSummary(id: 'other', fullName: 'Jamie Rep'), body: 'Hi there!'),
      ]
      ..messagesTotalToReturn = 1;

    await _pumpConversationDetailScreen(tester, repository: repo);

    expect(find.text('Hi there!'), findsOneWidget);
    expect(find.text('Jamie Rep'), findsOneWidget);
  });

  testWidgets('shows an empty state when the conversation has no messages', (tester) async {
    final repo = FakeMessagingRepository();

    await _pumpConversationDetailScreen(tester, repository: repo);

    expect(find.text('No messages yet. Say hello!'), findsOneWidget);
  });

  testWidgets("does not show the sender name on the current user's own messages", (tester) async {
    // testMembership('m1', ...) in the pump helper makes 'm1' the
    // current member id — a message sent by 'm1' is "mine".
    final repo = FakeMessagingRepository()
      ..messagesToReturn = [
        testMessage(id: 'msg-1', senderMember: const MemberSummary(id: 'm1', fullName: 'Me'), body: 'My own message'),
      ]
      ..messagesTotalToReturn = 1;

    await _pumpConversationDetailScreen(tester, repository: repo);

    expect(find.text('My own message'), findsOneWidget);
    expect(find.text('Me'), findsNothing);
  });

  testWidgets('opening the conversation marks it read', (tester) async {
    final repo = FakeMessagingRepository()
      ..messagesToReturn = [testMessage(id: 'msg-1')]
      ..messagesTotalToReturn = 1;

    await _pumpConversationDetailScreen(tester, repository: repo, conversationId: 'conv-42');

    expect(repo.markReadCallCount, 1);
    expect(repo.lastMarkReadConversationId, 'conv-42');
  });

  testWidgets('the send button is disabled for empty or whitespace-only text', (tester) async {
    final repo = FakeMessagingRepository();
    await _pumpConversationDetailScreen(tester, repository: repo);

    expect(tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.send), matching: find.byType(IconButton))).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.send), matching: find.byType(IconButton))).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Hello!');
    await tester.pump();
    expect(tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.send), matching: find.byType(IconButton))).onPressed, isNotNull);
  });

  testWidgets('sending a message clears the composer and shows the new message', (tester) async {
    final repo = FakeMessagingRepository();
    await _pumpConversationDetailScreen(tester, repository: repo);

    await tester.enterText(find.byType(TextField), 'Hello!');
    await tester.pump();
    await tester.tap(find.ancestor(of: find.byIcon(Icons.send), matching: find.byType(IconButton)));
    await tester.pumpAndSettle();

    expect(repo.lastSentBody, 'Hello!');
    expect(find.text('Hello!'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '');
  });
}
