import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/follow_up_api_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/follow_up_repository_impl.dart';
import '../../domain/entities/follow_up.dart';
import '../../domain/entities/follow_up_detail_state.dart';
import '../../domain/entities/follow_up_form_state.dart';
import '../../domain/entities/follow_up_list_state.dart';
import '../../domain/repositories/follow_up_repository.dart';
import '../controllers/follow_up_detail_controller.dart';
import '../controllers/follow_up_form_controller.dart';
import '../controllers/follow_up_list_controller.dart';

final followUpApiDataSourceProvider = Provider<FollowUpApiDataSource>((ref) => DioFollowUpApiDataSource());

final followUpRepositoryProvider = Provider<FollowUpRepository>((ref) {
  return FollowUpRepositoryImpl(ref.watch(followUpApiDataSourceProvider));
});

final followUpListControllerProvider = StateNotifierProvider.autoDispose<FollowUpListController, FollowUpListState>((ref) {
  return FollowUpListController(ref.watch(followUpRepositoryProvider), ref);
});

final followUpDetailControllerProvider =
    StateNotifierProvider.autoDispose.family<FollowUpDetailController, FollowUpDetailState, String>((ref, followUpId) {
  return FollowUpDetailController(ref.watch(followUpRepositoryProvider), ref, followUpId);
});

final followUpFormControllerProvider = StateNotifierProvider.autoDispose<FollowUpFormController, FollowUpFormState>((ref) {
  return FollowUpFormController(ref.watch(followUpRepositoryProvider), ref);
});

/// A specific lead's follow-ups (Phase 7 §2B, Lead Detail's follow-up
/// section) — `.family` keyed by leadId so it's only fetched when a
/// Lead Detail screen for that lead is actually built (§12: "fetch
/// lead-specific follow-ups only when required"), not as part of every
/// lead load.
final leadFollowUpsProvider = FutureProvider.autoDispose.family<List<FollowUp>, String>((ref, leadId) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(followUpRepositoryProvider);
  return repository.listLeadFollowUps(accessToken: user.accessToken, workspaceId: workspace.workspace.id, leadId: leadId);
});
