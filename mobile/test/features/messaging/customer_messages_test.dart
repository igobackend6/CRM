import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/customer360/presentation/providers/customer360_providers.dart';
import 'package:mobile/features/customer360/presentation/screens/customer_detail_screen.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../calls/fake_call_repository.dart';
import '../customer360/fake_customer_repository.dart';
import '../documents/fake_document_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_messaging_repository.dart';

/// Verifies Phase 16 §"Lead/Customer entry" from Customer 360 — the same
/// `MessagesEntryButton` Lead Detail uses (a customer IS a lead, so one
/// widget serves both), mirrors customer_calls_test.dart's pump helper.
Future<void> _pumpCustomerDetail(
  WidgetTester tester, {
  required FakeCustomerRepository customerRepository,
  required FakeMessagingRepository messagingRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const CustomerDetailScreen(customerId: 'c1')),
      ...extraRoutes,
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        customerRepositoryProvider.overrideWithValue(customerRepository),
        callRepositoryProvider.overrideWithValue(FakeCallRepository()),
        messagingRepositoryProvider.overrideWithValue(messagingRepository),
        documentRepositoryProvider.overrideWithValue(FakeDocumentRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a "Messages" entry point', (tester) async {
    final customerRepo = FakeCustomerRepository()..customerToReturn = testCustomer(id: 'c1');
    final messagingRepo = FakeMessagingRepository();

    await _pumpCustomerDetail(tester, customerRepository: customerRepo, messagingRepository: messagingRepo);

    expect(find.text('Messages'), findsOneWidget);
  });

  testWidgets('tapping "Messages" resolves the conversation and navigates to it', (tester) async {
    final customerRepo = FakeCustomerRepository()..customerToReturn = testCustomer(id: 'c1');
    final messagingRepo = FakeMessagingRepository()..conversationToReturn = testConversation(id: 'conv-7', leadId: 'c1');

    await _pumpCustomerDetail(
      tester,
      customerRepository: customerRepo,
      messagingRepository: messagingRepo,
      extraRoutes: [
        GoRoute(path: '/app/messages/conv-7', builder: (context, state) => const Scaffold(body: Text('CONVERSATION_DETAIL_MARKER'))),
      ],
    );

    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();

    expect(messagingRepo.lastGetOrCreateLeadId, 'c1');
    expect(find.text('CONVERSATION_DETAIL_MARKER'), findsOneWidget);
  });
}
