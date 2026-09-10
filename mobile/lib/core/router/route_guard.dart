import '../../features/auth/domain/entities/auth_state.dart';
import '../../features/workspace/domain/entities/workspace_state.dart';
import 'route_paths.dart';

/// Pure auth/workspace-aware redirect decision — no BuildContext, no
/// GoRouterState, so it's unit-testable directly (Phase 4 §15
/// "Routing" tests). Returns null to allow the requested location,
/// otherwise the location to redirect to instead.
///
/// State machine (Phase 4 §8):
///   initializing            -> /splash
///   unauthenticated/
///   authenticating/error    -> /login
///   authenticated + workspace loading -> /splash
///   authenticated + workspace none/error/needsSelection -> /workspace
///   authenticated + workspace selected -> /app (or any /app/* child —
///     Phase 4 only had the bare /app shell; Phase 5 adds nested leads
///     routes under it, so "selected" must allow the whole subtree, not
///     just an exact match on /app itself)
String? resolveRedirect({
  required AuthState auth,
  required WorkspaceState workspace,
  required String location,
}) {
  if (auth.status == AuthStatus.initializing) {
    return location == RoutePaths.splash ? null : RoutePaths.splash;
  }

  final hasNoSession = auth.status == AuthStatus.unauthenticated ||
      auth.status == AuthStatus.authenticating ||
      auth.status == AuthStatus.error;
  if (hasNoSession) {
    return location == RoutePaths.login ? null : RoutePaths.login;
  }

  // auth.status == AuthStatus.authenticated from here on.
  switch (workspace.status) {
    case WorkspaceStatus.loading:
      return location == RoutePaths.splash ? null : RoutePaths.splash;
    case WorkspaceStatus.none:
    case WorkspaceStatus.error:
    case WorkspaceStatus.needsSelection:
      return location == RoutePaths.workspace ? null : RoutePaths.workspace;
    case WorkspaceStatus.selected:
      final withinApp = location == RoutePaths.app || location.startsWith('${RoutePaths.app}/');
      return withinApp ? null : RoutePaths.app;
  }
}
