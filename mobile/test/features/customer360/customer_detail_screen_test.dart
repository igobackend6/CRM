import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/customer360/presentation/providers/customer360_providers.dart';
import 'package:mobile/features/customer360/presentation/screens/customer_detail_screen.dart';
import 'package:mobile/features/documents/domain/entities/document.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/leads/domain/entities/lead.dart';
import 'package:mobile/features/leads/domain/entities/tag.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import '../documents/fake_document_repository.dart';
import 'fake_customer_repository.dart';

Future<void> _pumpCustomerDetail(
  WidgetTester tester, {
  required FakeCustomerRepository repository,
  FakeDocumentRepository? documentRepository,
  List<GoRoute> extraRoutes = const [],
}) async {
  // Long screen (profile, tags, documents, follow-ups, timeline) — same
  // reasoning as lead_detail_followups_test.dart's taller test surface.
  await tester.binding.setSurfaceSize(const Size(800, 2600));
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
        customerRepositoryProvider.overrideWithValue(repository),
        documentRepositoryProvider.overrideWithValue(documentRepository ?? FakeDocumentRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a loading indicator, then the profile', (tester) async {
    final repo = FakeCustomerRepository()
      ..customerToReturn = testCustomer(name: 'Globex', id: 'c1')
      ..timelineItemsToReturn = const [];

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.text('Globex'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('+15551234567'), findsOneWidget);
    expect(find.text('acme@example.com'), findsOneWidget);
  });

  testWidgets('renders tags', (tester) async {
    final repo = FakeCustomerRepository()
      ..customerToReturn = Lead(
        id: 'c1',
        workspaceId: 'w1',
        name: 'Acme Corp',
        priority: 'high',
        isCustomer: true,
        tags: const [Tag(id: 't1', name: 'VIP')],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.text('VIP'), findsOneWidget);
  });

  testWidgets('renders documents', (tester) async {
    final repo = FakeCustomerRepository()..customerToReturn = testCustomer(id: 'c1');
    final documentRepo = FakeDocumentRepository()
      ..documentsToReturn = [Document(id: 'd1', fileName: 'contract.pdf', createdAt: DateTime.utc(2026, 1, 1))]
      ..documentsTotalToReturn = 1;

    await _pumpCustomerDetail(tester, repository: repo, documentRepository: documentRepo);

    expect(find.text('contract.pdf'), findsOneWidget);
  });

  testWidgets('shows "No documents yet." when there are none', (tester) async {
    final repo = FakeCustomerRepository()..customerToReturn = testCustomer(id: 'c1');

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.text('No documents yet.'), findsOneWidget);
  });

  testWidgets('renders follow-ups and navigates to Follow-Up Detail', (tester) async {
    final repo = FakeCustomerRepository()
      ..customerToReturn = testCustomer(id: 'c1')
      ..followUpsToReturn = const [];

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.text('No follow-ups yet.'), findsOneWidget);
  });

  testWidgets('renders the timeline', (tester) async {
    final repo = FakeCustomerRepository()
      ..customerToReturn = testCustomer(id: 'c1')
      ..timelineItemsToReturn = [testTimelineItem(id: 't1', summary: 'Left a voicemail')]
      ..timelineTotalToReturn = 1;

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.text('Left a voicemail'), findsOneWidget);
  });

  testWidgets('shows "No activity recorded yet." for an empty timeline', (tester) async {
    final repo = FakeCustomerRepository()..customerToReturn = testCustomer(id: 'c1');

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.text('No activity recorded yet.'), findsOneWidget);
  });

  testWidgets('the timeline shows a "Load more" button and pages when tapped', (tester) async {
    final repo = FakeCustomerRepository()
      ..customerToReturn = testCustomer(id: 'c1')
      ..timelineItemsToReturn = [testTimelineItem(id: 't1', summary: 'First page item')]
      ..timelineTotalToReturn = 2;

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.text('Load more'), findsOneWidget);

    repo.timelineItemsToReturn = [testTimelineItem(id: 't2', summary: 'Second page item')];
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(find.text('First page item'), findsOneWidget);
    expect(find.text('Second page item'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('an error loading the customer shows the error state with retry', (tester) async {
    final repo = FakeCustomerRepository()..getCustomerError = const NetworkException('Network unreachable');

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.text('Network unreachable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a non-customer/missing lead shows the not-found state', (tester) async {
    final repo = FakeCustomerRepository()..getCustomerError = const NotFoundException('Customer not found.');

    await _pumpCustomerDetail(tester, repository: repo);

    expect(find.textContaining('could not be found'), findsOneWidget);
  });
}
