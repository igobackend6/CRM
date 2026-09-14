import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';
import 'package:mobile/features/followups/presentation/screens/follow_up_detail_screen.dart';
import 'package:mobile/features/followups/presentation/screens/follow_up_form_screen.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../leads/fake_lead_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_follow_up_repository.dart';

Future<ProviderScope> _screen({
  required Widget child,
  required FakeFollowUpRepository followUpRepository,
  FakeLeadRepository? leadRepository,
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      followUpRepositoryProvider.overrideWithValue(followUpRepository),
      leadRepositoryProvider.overrideWithValue(leadRepository ?? (FakeLeadRepository()..membersToReturn = [])),
    ],
    child: child,
  );
}

void main() {
  group('FollowUpFormScreen — create', () {
    Future<void> pumpCreate(WidgetTester tester, {required FakeFollowUpRepository repo, FakeLeadRepository? leadRepo}) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const FollowUpFormScreen(leadId: 'l1')),
        ],
      );
      await tester.pumpWidget(
        await _screen(
          followUpRepository: repo,
          leadRepository: leadRepo,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('submitting without a due date shows a validation message', (tester) async {
      final repo = FakeFollowUpRepository();
      await pumpCreate(tester, repo: repo);

      await tester.tap(find.text('Create follow-up'));
      await tester.pumpAndSettle();

      expect(find.text('Pick a due date and time.'), findsOneWidget);
    });

    testWidgets('shows a friendly message when opened without a leadId', (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (context, state) => const FollowUpFormScreen())],
      );
      await tester.pumpWidget(
        await _screen(
          followUpRepository: FakeFollowUpRepository(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open this from a lead\'s follow-ups section.'), findsOneWidget);
    });
  });

  group('FollowUpFormScreen — edit', () {
    // The edit form prefills by reading followUpDetailControllerProvider
    // synchronously (mirrors LeadFormScreen's _prefillIfEditing) — that
    // only has an already-resolved value if something is watching it,
    // same as real navigation: the Detail screen underneath (still
    // mounted, just covered) keeps it alive and loaded. So these tests
    // route through the real Detail screen first, then push to Edit,
    // instead of pumping FollowUpFormScreen(followUpId:) in isolation.
    Future<void> pumpEdit(WidgetTester tester, {required FakeFollowUpRepository repo, FakeLeadRepository? leadRepo}) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const FollowUpDetailScreen(followUpId: 'fu-1'),
            routes: [GoRoute(path: 'edit', builder: (context, state) => const FollowUpFormScreen(followUpId: 'fu-1'))],
          ),
        ],
      );
      await tester.pumpWidget(
        await _screen(followUpRepository: repo, leadRepository: leadRepo, child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      router.push('/edit');
      await tester.pumpAndSettle();
    }

    testWidgets('prefills from the existing follow-up and saves changes', (tester) async {
      final repo = FakeFollowUpRepository()
        ..followUpToReturn = testFollowUp(id: 'fu-1', leadName: 'Acme Corp', notes: 'Call back later');
      final leadRepo = FakeLeadRepository()..membersToReturn = [testMember('m2', 'Rep Two')];

      await pumpEdit(tester, repo: repo, leadRepo: leadRepo);

      expect(find.text('Edit follow-up'), findsOneWidget);
      expect(find.text('Call back later'), findsOneWidget);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(repo.lastUpdateFollowUpId, 'fu-1');
    });

    testWidgets('a validation error from the server is shown', (tester) async {
      final repo = FakeFollowUpRepository()
        ..followUpToReturn = testFollowUp(id: 'fu-1')
        ..updateError = const ValidationException('Selected member is not an active member of this workspace.');

      await pumpEdit(tester, repo: repo);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Selected member is not an active member of this workspace.'), findsOneWidget);
    });
  });
}
