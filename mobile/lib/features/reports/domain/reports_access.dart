const _managerRoles = {'manager', 'admin', 'ceo'};

/// Whether [roleName] is one the backend grants `reports.read` to
/// (manager/admin/ceo — never team_mate). Used client-side only to skip a
/// doomed Team/Pipeline request and explain why; it is never the security
/// boundary — the backend still enforces `Permission.REPORTS_READ` no
/// matter what this returns. A null role (membership not resolved yet)
/// counts as allowed so the request itself decides.
bool canViewTeamReports(String? roleName) => roleName == null || _managerRoles.contains(roleName);
