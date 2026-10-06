import 'package:mobile/features/dialer/presentation/providers/native_dialer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/core/utils/external_url_launcher.dart';
import 'package:mobile/core/widgets/widgets.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/documents/presentation/providers/document_providers.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/screens/lead_detail_screen.dart';
import 'package:mobile/features/leads/presentation/screens/lead_list_screen.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../ai/fake_ai_insight_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../documents/fake_document_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_lead_filter_storage.dart';
import 'fake_lead_repository.dart';
import '../dialer/fake_native_dialer_service.dart';

class _RecordingLauncher implements ExternalUrlLauncher {
  final List<Uri> launched = [];

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return true;
  }
}

Future<_RecordingLauncher> _pump(WidgetTester tester, {required Widget screen, required FakeLeadRepository repo}) async {
  final launcher = _RecordingLauncher();
  final authRepo = FakeAuthRepository()..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => screen),
      GoRoute(path: '/app/leads/:id', builder: (context, state) => Scaffold(body: Text('DETAIL ${state.pathParameters['id']}'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        leadRepositoryProvider.overrideWithValue(repo),
        leadContactLauncherProvider.overrideWithValue(launcher),
        nativeDialerServiceProvider.overrideWithValue(FakeNativeDialerService()),
        leadFilterStorageProvider.overrideWithValue(FakeLeadFilterStorage()),
        aiInsightRepositoryProvider.overrideWithValue(FakeAiInsightRepository()),
        documentRepositoryProvider.overrideWithValue(FakeDocumentRepository()),
        realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return launcher;
}

void main() {
  testWidgets('Lead details: the call buttons sit on the name line, at the right end of the header card', (tester) async {
    final repo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Suguna');
    await _pump(tester, screen: const LeadDetailScreen(leadId: 'l1'), repo: repo);

    final name = find.text('Suguna');
    final call = find.byKey(const Key('lead-call-button'));
    final whatsApp = find.byKey(const Key('lead-whatsapp-call-button'));
    final card = find.byType(AccentCard);

    // Same line as the name...
    expect((tester.getCenter(call).dy - tester.getCenter(name).dy).abs(), lessThan(20));
    expect((tester.getCenter(whatsApp).dy - tester.getCenter(name).dy).abs(), lessThan(20));
    // ...to its right, with Call before WhatsApp...
    expect(tester.getTopLeft(call).dx, greaterThan(tester.getTopRight(name).dx));
    expect(tester.getTopLeft(whatsApp).dx, greaterThan(tester.getTopRight(call).dx));
    // ...and pushed to the card's right edge rather than hugging the name.
    expect(tester.getTopRight(card).dx - tester.getTopRight(whatsApp).dx, lessThan(30));
  });

  testWidgets('Lead details: both buttons still work from their new spot', (tester) async {
    final repo = FakeLeadRepository()..leadToReturn = testLead(id: 'l1', name: 'Suguna');
    final launcher = await _pump(tester, screen: const LeadDetailScreen(leadId: 'l1'), repo: repo);

    await tester.tap(find.byKey(const Key('lead-call-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
    await tester.pump();

    expect(launcher.launched.first.scheme, 'tel');
    expect(launcher.launched.last.host, 'wa.me');
  });

  group('Allocations list rows', () {
    Future<_RecordingLauncher> pumpList(WidgetTester tester, FakeLeadRepository repo) => _pump(tester, screen: const LeadListScreen(), repo: repo);

    testWidgets('every row has the call and WhatsApp-call buttons to the right of the name', (tester) async {
      final repo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp'), testLead(id: 'l2', name: 'Globex')]
        ..totalToReturn = 2;
      await pumpList(tester, repo);

      expect(find.byKey(const Key('lead-call-button')), findsNWidgets(2));
      expect(find.byKey(const Key('lead-whatsapp-call-button')), findsNWidgets(2));

      final name = find.text('Acme Corp');
      final call = find.byKey(const Key('lead-call-button')).first;
      expect((tester.getCenter(call).dy - tester.getCenter(name).dy).abs(), lessThan(20));
      // The name's box stretches up to the buttons, so their edges may touch but never overlap.
      expect(tester.getTopLeft(call).dx, greaterThanOrEqualTo(tester.getTopRight(name).dx));
    });

    testWidgets('tapping a row button dials the number and does not open the lead', (tester) async {
      final repo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
        ..totalToReturn = 1;
      final launcher = await pumpList(tester, repo);

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pumpAndSettle();

      expect(launcher.launched.single.toString(), 'tel:+15551234567');
      expect(find.text('DETAIL l1'), findsNothing);
    });

    testWidgets('the WhatsApp-call button opens WhatsApp for that lead without opening the lead', (tester) async {
      final repo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
        ..totalToReturn = 1;
      final launcher = await pumpList(tester, repo);

      await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
      await tester.pumpAndSettle();

      expect(launcher.launched.single.toString(), 'https://wa.me/15551234567');
      expect(find.text('DETAIL l1'), findsNothing);
    });

    testWidgets('tapping the row itself still opens the lead', (tester) async {
      final repo = FakeLeadRepository()
        ..leadsToReturn = [testLead(id: 'l1', name: 'Acme Corp')]
        ..totalToReturn = 1;
      await pumpList(tester, repo);

      await tester.tap(find.text('Acme Corp'));
      await tester.pumpAndSettle();

      expect(find.text('DETAIL l1'), findsOneWidget);
    });
  });
}
