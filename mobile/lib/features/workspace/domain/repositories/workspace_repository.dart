import '../entities/workspace.dart';

abstract class WorkspaceRepository {
  /// Only active memberships — see workspace_members.status in
  /// docs/architecture/database.md.
  Future<List<WorkspaceMembership>> loadMemberships(String profileId);

  /// The only thing persisted for workspace selection (Phase 4 §7) — no
  /// duplicate/parallel session storage.
  Future<String?> readSelectedWorkspaceId();

  Future<void> saveSelectedWorkspaceId(String workspaceId);

  Future<void> clearSelectedWorkspaceId();
}
