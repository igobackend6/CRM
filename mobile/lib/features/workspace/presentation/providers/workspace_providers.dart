import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/storage/secure_storage_service.dart';
import '../../../../services/supabase/supabase_service.dart';
import '../../data/workspace_repository_impl.dart';
import '../../domain/entities/workspace_state.dart';
import '../../domain/repositories/workspace_repository.dart';
import '../controllers/workspace_controller.dart';

final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) {
  return WorkspaceRepositoryImpl(SupabaseService.client, SecureStorageService());
});

final workspaceControllerProvider = StateNotifierProvider<WorkspaceController, WorkspaceState>((ref) {
  return WorkspaceController(ref.watch(workspaceRepositoryProvider), ref);
});
