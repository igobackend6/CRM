import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/core/router/route_paths.dart';
import 'package:mobile/features/analytics/presentation/widgets/analytics_floating_tab.dart';
import 'package:mobile/features/app_shell/presentation/screens/app_shell_screen.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';
import 'package:mobile/features/notifications/presentation/providers/notification_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../calls/fake_call_repository.dart';
import '../dashboard/fake_dashboard_repository.dart';
import '../followups/fake_follow_up_repository.dart';
import '../workspace/fake_workspace_repository.dart';

void main() {
  testWidgets('the floating tab shows the Analytics glyph and reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: AnalyticsFloatingTab(onTap: () => taps++)))),
    );

    expect(find.byIcon(Icons.insights), findsOneWidget);
    await tester.tap(find.byType(AnalyticsFloatingTab));

    expect(taps, 1);
  });

  testWidgets('the Home screen carries the tab, and tapping it opens the Analytics hub', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authRepo = FakeAuthRepository()
      ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
    final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const AppShellScreen()),
        GoRoute(path: RoutePaths.analytics, builder: (context, state) => const Scaffold(body: Text('ANALYTICS HUB'))),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
          workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
          followUpRepositoryProvider.overrideWithValue(FakeFollowUpRepository()),
          callRepositoryProvider.overrideWithValue(FakeCallRepository()),
          unreadNotificationCountProvider.overrideWith((ref) async => 0),
          realtimeServiceProvider.overrideWithValue(FakeRealtimeService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('analytics-floating-tab')), findsOneWidget);

    await tester.tap(find.byKey(const Key('analytics-floating-tab')));
    await tester.pumpAndSettle();

    expect(find.text('ANALYTICS HUB'), findsOneWidget);
  });

  testWidgets("the tab hugs the screen's right edge", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(children: [Align(alignment: const Alignment(1, -0.45), child: AnalyticsFloatingTab(onTap: () {}))]),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(AnalyticsFloatingTab));
    expect(rect.right, tester.view.physicalSize.width / tester.view.devicePixelRatio);
  });
}
