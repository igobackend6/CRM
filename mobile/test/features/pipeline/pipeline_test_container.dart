import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/realtime/realtime_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/pipeline/presentation/providers/pipeline_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../core/realtime/fake_realtime_service.dart';
import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_pipeline_repository.dart';

/// Mirrors dashboard_test_container.dart's buildDashboardTestContainer —
/// a real, authenticated session with a single selected workspace
/// already established.
Future<ProviderContainer> buildPipelineTestContainer({
  FakePipelineRepository? pipelineRepository,
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
      pipelineRepositoryProvider.overrideWithValue(pipelineRepository ?? FakePipelineRepository()),
      realtimeServiceProvider.overrideWithValue(realtimeService ?? FakeRealtimeService()),
    ],
  );

  await waitUntil(() => container.read(workspaceControllerProvider).selected != null);
  return container;
}

ProviderSubscription<T> keepAlive<T>(ProviderContainer container, ProviderListenable<T> provider) {
  return container.listen(provider, (_, _) {});
}
