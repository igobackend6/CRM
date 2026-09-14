import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';
import 'package:mobile/features/followups/presentation/screens/follow_up_detail_screen.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_follow_up_repository.dart';

Future<void> _pumpDetail(WidgetTester tester, {required FakeFollowUpRepository repository}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (context, state) => const FollowUpDetailScreen(followUpId: 'fu-1'))],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
        workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
        followUpRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('displays the follow-up details', (tester) async {
    final repo = FakeFollowUpRepository()
      ..followUpToReturn = testFollowUp(
        id: 'fu-1',
        leadName: 'Acme Corp',
        assignedMember: const MemberSummary(id: 'm2', fullName: 'Rep Two'),
        notes: 'Confirm budget',
      );

    await _pumpDetail(tester, repository: repo);

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Rep Two'), findsOneWidget);
    expect(find.text('Confirm budget'), findsOneWidget);
    // Pending -> both quick actions are shown.
    expect(find.text('Mark complete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('marking complete hides the quick actions', (tester) async {
    final repo = FakeFollowUpRepository()..followUpToReturn = testFollowUp(id: 'fu-1');

    await _pumpDetail(tester, repository: repo);
    await tester.tap(find.text('Mark complete'));
    await tester.pumpAndSettle();

    expect(repo.lastStatus, 'completed');
    expect(find.text('Mark complete'), findsNothing);
    expect(find.text('completed'), findsOneWidget);
  });

  testWidgets('a not-found follow-up shows the not-found message', (tester) async {
    final repo = FakeFollowUpRepository()..getError = const NotFoundException('Follow-up not found.');

    await _pumpDetail(tester, repository: repo);

    expect(find.text('This follow-up could not be found.'), findsOneWidget);
  });
}
