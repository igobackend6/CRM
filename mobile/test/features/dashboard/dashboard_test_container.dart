import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/calls/presentation/providers/call_providers.dart';
import 'package:mobile/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:mobile/features/followups/presentation/providers/followup_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../calls/fake_call_repository.dart';
import '../followups/fake_follow_up_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_dashboard_repository.dart';

/// Mirrors call_test_container.dart's buildCallTestContainer — a real,
/// authenticated session with a single selected workspace already
/// established. Also overrides `followUpRepositoryProvider`/
/// `callRepositoryProvider` since the dashboard's preview sections reuse
/// those unchanged (see dashboard_providers.dart's own note).
Future<ProviderContainer> buildDashboardTestContainer({
  FakeDashboardRepository? dashboardRepository,
  FakeFollowUpRepository? followUpRepository,
  FakeCallRepository? callRepository,
  FakeRealtimeService? realtimeService,
}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', email: 'rep@example.com');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      dashboardRepositoryProvider.overrideWithValue(dashboardRepository ?? FakeDashboardRepository()),
      followUpRepositoryProvider.overrideWithValue(followUpRepository ?? FakeFollowUpRepository()),
      callRepositoryProvider.overrideWithValue(callRepository ?? FakeCallRepository()),
      realtimeServiceProvider.overrideWithValue(realtimeService ?? FakeRealtimeService()),
    ],
  );

  await waitUntil(() => container.read(workspaceControllerProvider).selected != null);
  return container;
}

ProviderSubscription<T> keepAlive<T>(ProviderContainer container, ProviderListenable<T> provider) {
  return container.listen(provider, (_, _) {});
}
