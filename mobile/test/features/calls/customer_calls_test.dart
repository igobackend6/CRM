import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/core/widgets/widgets.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/customer360/presentation/providers/customer360_providers.dart';
import 'package:mobile/features/customer360/presentation/screens/customer_detail_screen.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../customer360/fake_customer_repository.dart';
import '../documents/fake_document_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_call_repository.dart';

/// Verifies Phase 9 §7's integration point: Customer 360 shows a Calls
/// section fed by the calls feature's [leadCallsProvider] (customer_id
/// IS a lead_id — no second endpoint, no second aggregation path), and
/// that real call records also surface through the existing Phase 8
/// unified timeline unchanged.
Future<void> _pumpCustomerDetail(
  WidgetTester tester, {
  required FakeCustomerRepository customerRepository,
  required FakeCallRepository callRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
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
        callRepositoryProvider.overrideWithValue(callRepository),
        documentRepositoryProvider.overrideWithValue(FakeDocumentRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the customer\'s calls', (tester) async {
    final customerRepo = FakeCustomerRepository()..customerToReturn = testCustomer(id: 'c1');
    final callRepo = FakeCallRepository()..leadCallsToReturn = [testCall(id: 'call-1', leadId: 'c1', direction: 'outbound')];

    await _pumpCustomerDetail(tester, customerRepository: customerRepo, callRepository: callRepo);

    // Phase 15 also adds an "Calls" activity-filter chip elsewhere on this
    // screen, so a bare find.text('Calls') is no longer unique — scope to
    // the section header specifically.
    expect(find.widgetWithText(SectionHeader, 'Calls'), findsOneWidget);
    expect(find.byIcon(Icons.call_made), findsWidgets);
  });

  testWidgets('shows "No calls logged yet." when there are none', (tester) async {
    final customerRepo = FakeCustomerRepository()..customerToReturn = testCustomer(id: 'c1');
    final callRepo = FakeCallRepository();

    await _pumpCustomerDetail(tester, customerRepository: customerRepo, callRepository: callRepo);

    expect(find.text('No calls logged yet.'), findsOneWidget);
  });

  testWidgets('real call rows also appear in the unified timeline', (tester) async {
    final customerRepo = FakeCustomerRepository()
      ..customerToReturn = testCustomer(id: 'c1')
      ..timelineItemsToReturn = [testTimelineItem(id: 'call:call-1', type: 'call', summary: 'Outbound call — ended')]
      ..timelineTotalToReturn = 1;
    final callRepo = FakeCallRepository();

    await _pumpCustomerDetail(tester, customerRepository: customerRepo, callRepository: callRepo);

    expect(find.text('Outbound call — ended'), findsOneWidget);
  });

  testWidgets('"Log call" navigates to the create form for this customer\'s lead', (tester) async {
    final customerRepo = FakeCustomerRepository()..customerToReturn = testCustomer(id: 'c1');
    final callRepo = FakeCallRepository();

    await _pumpCustomerDetail(
      tester,
      customerRepository: customerRepo,
      callRepository: callRepo,
      extraRoutes: [
        GoRoute(
          path: '/app/calls/create',
          builder: (context, state) => Scaffold(body: Text('CREATE_MARKER leadId=${state.uri.queryParameters['leadId']}')),
        ),
      ],
    );

    await tester.tap(find.text('Log call'));
    await tester.pumpAndSettle();

    expect(find.text('CREATE_MARKER leadId=c1'), findsOneWidget);
  });
}
