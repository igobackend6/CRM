import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/errors/app_exception.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../domain/entities/workspace.dart';
import '../domain/repositories/workspace_repository.dart';

const _selectedWorkspaceKey = 'selected_workspace_id';

class WorkspaceRepositoryImpl implements WorkspaceRepository {
  WorkspaceRepositoryImpl(this._client, this._storage);

  final supa.SupabaseClient _client;
  final SecureStorageService _storage;

  @override
  Future<List<WorkspaceMembership>> loadMemberships(String profileId) async {
    try {
      final rows = await _client
          .from('workspace_members')
          .select('id, workspace:workspaces(id, name, slug), role:roles(name)')
          .eq('profile_id', profileId)
          .eq('status', 'active');
      return (rows as List).cast<Map<String, dynamic>>().map(WorkspaceMembership.fromJson).toList();
    } catch (e, st) {
      // TEMP diagnostic (Phase 21C follow-up debugging) — remove once the
      // real cause of "Could not load your workspaces" on-device is found.
      // ignore: avoid_print
      print('DEBUG loadMemberships failed: $e\n$st');
      throw NetworkException('Could not load your workspaces.', cause: e);
    }
  }

  @override
  Future<String?> readSelectedWorkspaceId() => _storage.read(_selectedWorkspaceKey);

  @override
  Future<void> saveSelectedWorkspaceId(String workspaceId) => _storage.write(_selectedWorkspaceKey, workspaceId);

  @override
  Future<void> clearSelectedWorkspaceId() => _storage.delete(_selectedWorkspaceKey);
}
