/// Mirrors `workspaces` (supabase/migrations/000003_workspaces.sql) —
/// only the fields this app actually reads.
class Workspace {
  const Workspace({required this.id, required this.name, required this.slug});

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
    );
  }

  final String id;
  final String name;
  final String slug;
}

/// One row of `workspace_members`, joined with its workspace and role
/// name — what the workspace-selection screen and app shell need.
class WorkspaceMembership {
  const WorkspaceMembership({required this.memberId, required this.workspace, required this.roleName});

  factory WorkspaceMembership.fromJson(Map<String, dynamic> json) {
    return WorkspaceMembership(
      memberId: json['id'] as String,
      workspace: Workspace.fromJson(json['workspace'] as Map<String, dynamic>),
      roleName: (json['role'] as Map<String, dynamic>?)?['name'] as String? ?? 'team_mate',
    );
  }

  final String memberId;
  final Workspace workspace;
  final String roleName;
}
