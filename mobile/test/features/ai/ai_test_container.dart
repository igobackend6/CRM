import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/ai/presentation/providers/ai_providers.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import '../workspace/fake_workspace_repository.dart';
import 'fake_ai_insight_repository.dart';

/// Mirrors rechurn_test_container.dart's buildRechurnTestContainer — a
/// real, authenticated session with a single selected workspace already
/// established.
Future<ProviderContainer> buildAiTestContainer({FakeAiInsightRepository? aiInsightRepository}) async {
  final authRepo = FakeAuthRepository()
    ..session = const SessionInfo(userId: 'u1', accessToken: 'token-1', phone: '+919876543210');
  final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme'))];

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
      workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
      aiInsightRepositoryProvider.overrideWithValue(aiInsightRepository ?? FakeAiInsightRepository()),
    ],
  );

  await waitUntil(() => container.read(workspaceControllerProvider).selected != null);
  return container;
}

ProviderSubscription<T> keepAlive<T>(ProviderContainer container, ProviderListenable<T> provider) {
  return container.listen(provider, (_, _) {});
}
