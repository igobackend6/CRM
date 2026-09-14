import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/router/route_guard.dart';
import 'package:mobile/core/router/route_paths.dart';
import 'package:mobile/features/auth/domain/entities/app_user.dart';
import 'package:mobile/features/auth/domain/entities/auth_state.dart';
import 'package:mobile/features/auth/domain/entities/profile.dart';
import 'package:mobile/features/workspace/domain/entities/workspace.dart';
import 'package:mobile/features/workspace/domain/entities/workspace_state.dart';

final _user = AppUser(
  id: 'u1',
  phone: '+919876543210',
  accessToken: 't1',
  profile: const Profile(id: 'u1', fullName: 'Test User'),
);

final _workspace = Workspace(id: 'w1', name: 'Acme', slug: 'acme');
final _membership = WorkspaceMembership(memberId: 'm1', workspace: _workspace, roleName: 'team_mate');

void main() {
  group('resolveRedirect', () {
    test('initializing -> /splash', () {
      expect(
        resolveRedirect(auth: const AuthState.initializing(), workspace: const WorkspaceState.loading(), location: RoutePaths.login),
        RoutePaths.splash,
      );
    });

    test('unauthenticated -> /login', () {
      expect(
        resolveRedirect(auth: const AuthState.unauthenticated(), workspace: const WorkspaceState.loading(), location: RoutePaths.app),
        RoutePaths.login,
      );
    });

    test('unauthenticated user cannot access /app', () {
      expect(
        resolveRedirect(auth: const AuthState.unauthenticated(), workspace: const WorkspaceState.loading(), location: RoutePaths.app),
        RoutePaths.login,
      );
    });

    test('mustChangePassword -> /change-password', () {
      expect(
        resolveRedirect(
          auth: const AuthState.mustChangePassword(),
          workspace: const WorkspaceState.loading(),
          location: RoutePaths.app,
        ),
        RoutePaths.changePassword,
      );
    });

    test('mustChangePassword already at /change-password -> no redirect', () {
      expect(
        resolveRedirect(
          auth: const AuthState.mustChangePassword(),
          workspace: const WorkspaceState.loading(),
          location: RoutePaths.changePassword,
        ),
        isNull,
      );
    });

    test('authenticated + single/selected workspace -> /app', () {
      expect(
        resolveRedirect(
          auth: AuthState.authenticated(_user),
          workspace: WorkspaceState.selected([_membership], _membership),
          location: RoutePaths.splash,
        ),
        RoutePaths.app,
      );
    });

    test('authenticated user cannot access /login', () {
      expect(
        resolveRedirect(
          auth: AuthState.authenticated(_user),
          workspace: WorkspaceState.selected([_membership], _membership),
          location: RoutePaths.login,
        ),
        RoutePaths.app,
      );
    });

    test('authenticated + multiple workspaces -> /workspace', () {
      final second = WorkspaceMembership(
        memberId: 'm2',
        workspace: const Workspace(id: 'w2', name: 'Globex', slug: 'globex'),
        roleName: 'manager',
      );
      expect(
        resolveRedirect(
          auth: AuthState.authenticated(_user),
          workspace: WorkspaceState.needsSelection([_membership, second]),
          location: RoutePaths.splash,
        ),
        RoutePaths.workspace,
      );
    });

    test('authenticated + zero workspaces -> /workspace (shows the "no workspace" message)', () {
      expect(
        resolveRedirect(auth: AuthState.authenticated(_user), workspace: const WorkspaceState.none(), location: RoutePaths.splash),
        RoutePaths.workspace,
      );
    });

    test('authenticated + selected workspace -> nested /app/leads routes are allowed, not bounced to /app', () {
      // Phase 5: /app grew children (leads list/detail/create/edit).
      // "selected" must permit the whole /app/* subtree, not just an
      // exact match on /app itself.
      expect(
        resolveRedirect(
          auth: AuthState.authenticated(_user),
          workspace: WorkspaceState.selected([_membership], _membership),
          location: '/app/leads',
        ),
        isNull,
      );
      expect(
        resolveRedirect(
          auth: AuthState.authenticated(_user),
          workspace: WorkspaceState.selected([_membership], _membership),
          location: '/app/leads/lead-123/edit',
        ),
        isNull,
      );
    });

    test('already at the target location -> no redirect (loop prevention)', () {
      expect(
        resolveRedirect(
          auth: AuthState.authenticated(_user),
          workspace: WorkspaceState.selected([_membership], _membership),
          location: RoutePaths.app,
        ),
        isNull,
      );
      expect(
        resolveRedirect(auth: const AuthState.unauthenticated(), workspace: const WorkspaceState.loading(), location: RoutePaths.login),
        isNull,
      );
    });
  });
}
