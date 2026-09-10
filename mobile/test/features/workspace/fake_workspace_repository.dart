import 'package:mobile/features/workspace/domain/entities/workspace.dart';
import 'package:mobile/features/workspace/domain/repositories/workspace_repository.dart';

class FakeWorkspaceRepository implements WorkspaceRepository {
  List<WorkspaceMembership> membershipsToReturn = [];
  String? storedSelectedId;
  bool clearCalled = false;

  @override
  Future<List<WorkspaceMembership>> loadMemberships(String profileId) async => membershipsToReturn;

  @override
  Future<String?> readSelectedWorkspaceId() async => storedSelectedId;

  @override
  Future<void> saveSelectedWorkspaceId(String workspaceId) async {
    storedSelectedId = workspaceId;
  }

  @override
  Future<void> clearSelectedWorkspaceId() async {
    clearCalled = true;
    storedSelectedId = null;
  }
}

Workspace testWorkspace(String id, String name) => Workspace(id: id, name: name, slug: name.toLowerCase());

WorkspaceMembership testMembership(String memberId, Workspace workspace, {String role = 'team_mate'}) =>
    WorkspaceMembership(memberId: memberId, workspace: workspace, roleName: role);
