import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/domain/entities/session_info.dart';
import 'package:mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:mobile/features/workspace/domain/entities/workspace_state.dart';
import 'package:mobile/features/workspace/presentation/providers/workspace_providers.dart';

import '../../helpers/wait_until.dart';
import '../../services/api/fake_me_api_data_source.dart';
import '../auth/fake_auth_repository.dart';
import 'fake_workspace_repository.dart';

/// Uses a real ProviderContainer (rather than constructing
/// WorkspaceController by hand) so these tests exercise the actual
/// production wiring: WorkspaceController reacting to authControllerProvider
/// via `ref.listen`, not a re-implementation of it.
ProviderContainer buildContainer({
  required FakeAuthRepository authRepo,
  required FakeWorkspaceRepository workspaceRepo,
}) {
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(authRepo),
    meApiDataSourceProvider.overrideWithValue(FakeMeApiDataSource()),
    workspaceRepositoryProvider.overrideWithValue(workspaceRepo),
  ]);
  return container;
}

void main() {
  group('WorkspaceController (via ProviderContainer)', () {
    test('zero memberships -> none, and clears any stored selection', () async {
      final authRepo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', email: 'a@b.com');
      final workspaceRepo = FakeWorkspaceRepository()
        ..membershipsToReturn = []
        ..storedSelectedId = 'leftover-id';
      final container = buildContainer(authRepo: authRepo, workspaceRepo: workspaceRepo);
      addTearDown(container.dispose);

      container.read(workspaceControllerProvider);
      await waitUntil(() => container.read(workspaceControllerProvider).status == WorkspaceStatus.none);

      expect(workspaceRepo.clearCalled, isTrue);
    });

    test('one membership -> auto-selected and persisted', () async {
      final authRepo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', email: 'a@b.com');
      final ws = testWorkspace('w1', 'Acme');
      final workspaceRepo = FakeWorkspaceRepository()..membershipsToReturn = [testMembership('m1', ws)];
      final container = buildContainer(authRepo: authRepo, workspaceRepo: workspaceRepo);
      addTearDown(container.dispose);

      container.read(workspaceControllerProvider);
      await waitUntil(() => container.read(workspaceControllerProvider).status == WorkspaceStatus.selected);

      final state = container.read(workspaceControllerProvider);
      expect(state.selected!.workspace.id, 'w1');
      expect(workspaceRepo.storedSelectedId, 'w1');
    });

    test('multiple memberships with no prior selection -> needsSelection', () async {
      final authRepo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', email: 'a@b.com');
      final workspaceRepo = FakeWorkspaceRepository()
        ..membershipsToReturn = [
          testMembership('m1', testWorkspace('w1', 'Acme')),
          testMembership('m2', testWorkspace('w2', 'Globex')),
        ];
      final container = buildContainer(authRepo: authRepo, workspaceRepo: workspaceRepo);
      addTearDown(container.dispose);

      container.read(workspaceControllerProvider);
      await waitUntil(() => container.read(workspaceControllerProvider).status == WorkspaceStatus.needsSelection);

      expect(container.read(workspaceControllerProvider).memberships, hasLength(2));
    });

    test('selecting a workspace transitions to selected and persists it', () async {
      final authRepo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', email: 'a@b.com');
      final target = testMembership('m2', testWorkspace('w2', 'Globex'));
      final workspaceRepo = FakeWorkspaceRepository()
        ..membershipsToReturn = [testMembership('m1', testWorkspace('w1', 'Acme')), target];
      final container = buildContainer(authRepo: authRepo, workspaceRepo: workspaceRepo);
      addTearDown(container.dispose);

      container.read(workspaceControllerProvider);
      await waitUntil(() => container.read(workspaceControllerProvider).status == WorkspaceStatus.needsSelection);

      await container.read(workspaceControllerProvider.notifier).select(target);

      final state = container.read(workspaceControllerProvider);
      expect(state.status, WorkspaceStatus.selected);
      expect(state.selected!.workspace.id, 'w2');
      expect(workspaceRepo.storedSelectedId, 'w2');
    });

    test('stale persisted selection is cleared and re-resolved', () async {
      final authRepo = FakeAuthRepository()
        ..session = const SessionInfo(userId: 'u1', accessToken: 't1', email: 'a@b.com');
      final onlyMembership = testMembership('m1', testWorkspace('w1', 'Acme'));
      final workspaceRepo = FakeWorkspaceRepository()
        ..membershipsToReturn = [onlyMembership]
        ..storedSelectedId = 'no-longer-a-member-of-this-workspace';
      final container = buildContainer(authRepo: authRepo, workspaceRepo: workspaceRepo);
      addTearDown(container.dispose);

      container.read(workspaceControllerProvider);
      await waitUntil(() => container.read(workspaceControllerProvider).status == WorkspaceStatus.selected);

      // Stale id was cleared, then the single real membership was
      // auto-selected and persisted in its place.
      expect(workspaceRepo.clearCalled, isTrue);
      expect(workspaceRepo.storedSelectedId, 'w1');
    });
  });
}
