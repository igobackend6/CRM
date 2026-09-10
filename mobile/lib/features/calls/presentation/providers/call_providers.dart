import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/call_api_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/call_repository_impl.dart';
import '../../domain/entities/call.dart';
import '../../domain/entities/call_detail_state.dart';
import '../../domain/entities/call_form_state.dart';
import '../../domain/entities/call_list_state.dart';
import '../../domain/entities/call_outcome.dart';
import '../../domain/repositories/call_repository.dart';
import '../controllers/call_detail_controller.dart';
import '../controllers/call_form_controller.dart';
import '../controllers/call_list_controller.dart';

final callApiDataSourceProvider = Provider<CallApiDataSource>((ref) => DioCallApiDataSource());

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepositoryImpl(ref.watch(callApiDataSourceProvider));
});

final callListControllerProvider = StateNotifierProvider.autoDispose<CallListController, CallListState>((ref) {
  return CallListController(ref.watch(callRepositoryProvider), ref);
});

/// Lead-scoped, paginated call list — powers Lead Detail's "View all
/// calls" (§6). `.family` keyed by leadId, distinct from the unscoped
/// [callListControllerProvider] (`/app/calls`) but built on the exact
/// same [CallListController]/[CallListState] — no duplicated list state
/// (§6/§10).
final leadCallListControllerProvider =
    StateNotifierProvider.autoDispose.family<CallListController, CallListState, String>((ref, leadId) {
  return CallListController(ref.watch(callRepositoryProvider), ref, leadId: leadId);
});

final callDetailControllerProvider =
    StateNotifierProvider.autoDispose.family<CallDetailController, CallDetailState, String>((ref, callId) {
  return CallDetailController(ref.watch(callRepositoryProvider), ref, callId);
});

final callFormControllerProvider = StateNotifierProvider.autoDispose<CallFormController, CallFormState>((ref) {
  return CallFormController(ref.watch(callRepositoryProvider), ref);
});

/// A specific lead's calls (Phase 9 §6, Lead Detail's Calls section; also
/// reused by Customer 360's Calls section, §7 — a customer IS a lead, so
/// the same lead-nested endpoint serves both without a second endpoint
/// or a second aggregation path). `.family` keyed by leadId so it's only
/// fetched when a screen for that lead is actually built, matching
/// `leadFollowUpsProvider`'s reasoning exactly.
final leadCallsProvider = FutureProvider.autoDispose.family<List<Call>, String>((ref, leadId) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(callRepositoryProvider);
  return repository.listLeadCalls(accessToken: user.accessToken, workspaceId: workspace.workspace.id, leadId: leadId);
});

/// Call outcomes for the current workspace (Phase 9 §5) — loaded once
/// per workspace selection and shared by the call log create form,
/// same pattern as `leadReferenceDataProvider`.
final callOutcomesProvider = FutureProvider.autoDispose<List<CallOutcome>>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(callRepositoryProvider);
  return repository.listCallOutcomes(accessToken: user.accessToken, workspaceId: workspace.workspace.id);
});
