import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/customer360/presentation/screens/customers_overview_screen.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../leads/fake_lead_repository.dart';
import '../workspace/fake_workspace_repository.dart';

/// The Customers tab is the shared lead list in customers mode (its header controls are covered in
/// test/features/leads/lead_list_screen_test.dart); these check the tab as the router builds it.
Future<void> _pump(WidgetTester tester, FakeLeadRepository repo) async {
  final authRepo = FakeAuthRepository()..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const CustomersOverviewScreen()),
      GoRoute(path: '/app/customers/:id', builder: (context, state) => Scaffold(body: Text('CUSTOMER 360 ${state.pathParameters['id']}'))),
      GoRoute(path: '/app/leads/create', builder: (context, state) => const Scaffold(body: Text('Create Lead Stub'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        leadRepositoryProvider.overrideWithValue(repo),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the customers the backend returns, asking only for customers', (tester) async {
    final repo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'c1', name: 'Suguna', isCustomer: true), testLead(id: 'c2', name: 'Globex', isCustomer: true)]
      ..totalToReturn = 2;

    await _pump(tester, repo);

    expect(find.text('Suguna'), findsOneWidget);
    expect(find.text('Globex'), findsOneWidget);
    expect(repo.lastIsCustomer, isTrue);
  });

  testWidgets('has the full header: status selector with a count, search, filters, pipeline board and more', (tester) async {
    final repo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'c1', name: 'Suguna', isCustomer: true)]
      ..totalToReturn = 1;

    await _pump(tester, repo);

    expect(find.byKey(const Key('allocations-status-selector')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('allocations-count-badge')), matching: find.text('1/1')), findsOneWidget);
    expect(find.byTooltip('Search customers'), findsOneWidget);
    expect(find.byTooltip('Filter leads'), findsOneWidget);
    expect(find.byTooltip('Pipeline view'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    // The old plain "Customers" title bar is gone.
    expect(find.text('Customers'), findsNothing);
  });

  testWidgets('tapping a customer opens its Customer 360 view', (tester) async {
    final repo = FakeLeadRepository()
      ..leadsToReturn = [testLead(id: 'c1', name: 'Suguna', isCustomer: true)]
      ..totalToReturn = 1;
    await _pump(tester, repo);

    await tester.tap(find.text('Suguna'));
    await tester.pumpAndSettle();

    expect(find.text('CUSTOMER 360 c1'), findsOneWidget);
  });

  testWidgets('a load failure shows Retry, and Retry loads the customers', (tester) async {
    final repo = FakeLeadRepository()
      ..listError = const NetworkException('offline')
      ..leadsToReturn = [testLead(id: 'c1', name: 'Suguna', isCustomer: true)]
      ..totalToReturn = 1;
    await _pump(tester, repo);
    expect(find.text('Retry'), findsOneWidget);

    repo.listError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Suguna'), findsOneWidget);
  });

  testWidgets('the add button still opens the create-lead form', (tester) async {
    await _pump(tester, FakeLeadRepository());

    await tester.tap(find.byTooltip('New lead'));
    await tester.pumpAndSettle();

    expect(find.text('Create Lead Stub'), findsOneWidget);
  });
}
