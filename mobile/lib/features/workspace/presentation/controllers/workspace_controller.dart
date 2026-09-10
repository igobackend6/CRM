import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/auth_state.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/workspace.dart';
import '../../domain/entities/workspace_state.dart';
import '../../domain/repositories/workspace_repository.dart';

/// Reacts to authControllerProvider rather than being driven directly by
/// AuthController — see the class doc on AuthController for why the two
/// are kept as separate controllers.
class WorkspaceController extends StateNotifier<WorkspaceState> {
  WorkspaceController(this._repository, Ref ref) : super(const WorkspaceState.loading()) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      final user = next.user;
      if (next.status == AuthStatus.authenticated && user != null) {
        if (previous?.user?.id != user.id) {
          loadForUser(user.profile.id);
        }
      } else {
        reset();
      }
    }, fireImmediately: true);
  }

  final WorkspaceRepository _repository;

  Future<void> loadForUser(String profileId) async {
    state = const WorkspaceState.loading();
    try {
      final memberships = await _repository.loadMemberships(profileId);

      if (memberships.isEmpty) {
        await _repository.clearSelectedWorkspaceId();
        state = const WorkspaceState.none();
        return;
      }

      final storedId = await _repository.readSelectedWorkspaceId();
      WorkspaceMembership? resolved;

      if (storedId != null) {
        for (final membership in memberships) {
          if (membership.workspace.id == storedId) {
            resolved = membership;
            break;
          }
        }
        if (resolved == null) {
          // Stale/invalid selection (Phase 4 §7) — clear it and fall
          // through to auto-select-if-single / require selection.
          AppLogger.info('Persisted workspace selection no longer valid; clearing.');
          await _repository.clearSelectedWorkspaceId();
        }
      }

      resolved ??= memberships.length == 1 ? memberships.first : null;

      if (resolved != null) {
        await _repository.saveSelectedWorkspaceId(resolved.workspace.id);
        state = WorkspaceState.selected(memberships, resolved);
      } else {
        state = WorkspaceState.needsSelection(memberships);
      }
    } catch (e) {
      AppLogger.error('Failed to load workspace memberships', error: e);
      state = const WorkspaceState.error('Could not load your workspaces. Pull to refresh to try again.');
    }
  }

  Future<void> select(WorkspaceMembership membership) async {
    await _repository.saveSelectedWorkspaceId(membership.workspace.id);
    state = WorkspaceState.selected(state.memberships, membership);
  }

  void reset() {
    state = const WorkspaceState.loading();
  }
}
