import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';

/// Everything a leads API call needs beyond its own arguments — resolved
/// fresh on every call (never cached) so it always reflects the current
/// session/workspace, same principle as AuthController reading the
/// token from SessionInfo per call.
class LeadRequestContext {
  const LeadRequestContext({required this.accessToken, required this.workspaceId});

  final String accessToken;
  final String workspaceId;
}

/// A provider-read function — matches both `Ref.read` (used by
/// StateNotifier controllers) and `WidgetRef.read` (used directly by
/// screens, e.g. the tag picker in lead_detail_screen.dart). The two
/// types don't share a common supertype in this Riverpod version, so
/// this accepts their shared method signature instead of either type.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Null when there's no authenticated user or no selected workspace —
/// the router (route_guard.dart) should never let a leads screen be
/// reachable in that state, but callers stay defensive rather than
/// assuming it. Call as `resolveLeadContext(ref.read)`.
LeadRequestContext? resolveLeadContext(ProviderReader read) {
  final user = read(authControllerProvider).user;
  final workspace = read(workspaceControllerProvider).selected;
  if (user == null || workspace == null) return null;
  return LeadRequestContext(accessToken: user.accessToken, workspaceId: workspace.workspace.id);
}
