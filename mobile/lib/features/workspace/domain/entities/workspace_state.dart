import 'workspace.dart';

/// Phase 4 §7 — zero/one/multiple membership handling, plus a stale
/// selection needing re-resolution. `loading` also covers "auth isn't
/// authenticated yet" (nothing to load), so the router can treat
/// anything other than `selected` uniformly as "not ready for /app".
enum WorkspaceStatus { loading, none, needsSelection, selected, error }

class WorkspaceState {
  const WorkspaceState._({
    required this.status,
    this.memberships = const [],
    this.selected,
    this.errorMessage,
  });

  const WorkspaceState.loading() : this._(status: WorkspaceStatus.loading);
  const WorkspaceState.none() : this._(status: WorkspaceStatus.none);
  const WorkspaceState.needsSelection(List<WorkspaceMembership> memberships)
      : this._(status: WorkspaceStatus.needsSelection, memberships: memberships);
  const WorkspaceState.selected(List<WorkspaceMembership> memberships, WorkspaceMembership selected)
      : this._(status: WorkspaceStatus.selected, memberships: memberships, selected: selected);
  const WorkspaceState.error(String message) : this._(status: WorkspaceStatus.error, errorMessage: message);

  final WorkspaceStatus status;
  final List<WorkspaceMembership> memberships;
  final WorkspaceMembership? selected;
  final String? errorMessage;
}
