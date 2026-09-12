import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/location_service.dart';
import '../../../../services/api/lead_api_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../customer360/domain/entities/timeline_list_state.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../data/lead_repository_impl.dart';
import '../../domain/entities/lead_detail_state.dart';
import '../../domain/entities/lead_form_state.dart';
import '../../domain/entities/lead_import_state.dart';
import '../../domain/entities/lead_list_state.dart';
import '../../domain/entities/lead_reference_data.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/saved_lead_view.dart';
import '../../domain/entities/tag.dart';
import '../../domain/repositories/lead_repository.dart';
import '../controllers/csv_file_picker.dart';
import '../controllers/lead_activity_controller.dart';
import '../controllers/lead_detail_controller.dart';
import '../controllers/lead_filter_storage.dart';
import '../controllers/lead_form_controller.dart';
import '../controllers/lead_import_controller.dart';
import '../controllers/lead_list_controller.dart';
import '../controllers/saved_views_controller.dart';

final leadApiDataSourceProvider = Provider<LeadApiDataSource>((ref) => DioLeadApiDataSource());

final leadRepositoryProvider = Provider<LeadRepository>((ref) {
  return LeadRepositoryImpl(ref.watch(leadApiDataSourceProvider));
});

/// The create form's "Others" section (Runo-reference layout) — a
/// provider seam over `geolocator` for the same testability reason as
/// documentFilePickerProvider/documentExternalUrlLauncherProvider.
final leadLocationServiceProvider = Provider<LocationService>((ref) => GeolocatorLocationService());

final leadListControllerProvider = StateNotifierProvider.autoDispose<LeadListController, LeadListState>((ref) {
  return LeadListController(ref.watch(leadRepositoryProvider), ref);
});

final leadDetailControllerProvider =
    StateNotifierProvider.autoDispose.family<LeadDetailController, LeadDetailState, String>((ref, leadId) {
  return LeadDetailController(ref.watch(leadRepositoryProvider), ref, leadId);
});

final leadFormControllerProvider = StateNotifierProvider.autoDispose<LeadFormController, LeadFormState>((ref) {
  return LeadFormController(ref.watch(leadRepositoryProvider), ref);
});

/// Lead Detail's unified activity feed (Phase 15) — one instance per
/// lead, mirrors `customerTimelineControllerProvider`'s `.family` shape.
final leadActivityControllerProvider =
    StateNotifierProvider.autoDispose.family<LeadActivityController, TimelineListState, String>((ref, leadId) {
  return LeadActivityController(ref.watch(leadRepositoryProvider), ref, leadId);
});

/// Statuses + sources for the current workspace (Phase 5 §5) — loaded
/// once per workspace selection and shared by the list filter and the
/// create/edit form, rather than each screen fetching its own copy.
final leadReferenceDataProvider = FutureProvider.autoDispose<LeadReferenceData>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) {
    return const LeadReferenceData(statuses: [], sources: []);
  }
  final repository = ref.watch(leadRepositoryProvider);
  final statuses = await repository.listStatuses(accessToken: user.accessToken, workspaceId: workspace.workspace.id);
  final sources = await repository.listSources(accessToken: user.accessToken, workspaceId: workspace.workspace.id);
  return LeadReferenceData(statuses: statuses, sources: sources);
});

/// Active workspace members for the assignment picker (Phase 6 §3).
/// FutureProvider caches this for as long as something watches it (or
/// within Riverpod's brief autoDispose grace period), so opening the
/// picker repeatedly within the same workspace/session doesn't re-fetch
/// on every open (Phase 6 §10: no duplicate/N+1 member requests).
final workspaceMembersProvider = FutureProvider.autoDispose<List<MemberSummary>>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(leadRepositoryProvider);
  return repository.listWorkspaceMembers(accessToken: user.accessToken, workspaceId: workspace.workspace.id);
});

// ---- CSV import (Phase 13) ----

final csvFilePickerProvider = Provider<CsvFilePicker>((ref) => FilePickerCsvFilePicker());

/// A fresh idle state every time the import sheet reopens (autoDispose:
/// nothing keeps this alive once the sheet that watches it is popped).
final leadImportControllerProvider = StateNotifierProvider.autoDispose<LeadImportController, LeadImportState>((ref) {
  return LeadImportController(ref.watch(leadRepositoryProvider), ref.watch(csvFilePickerProvider), ref);
});

// ---- advanced filters & saved views (Phase 14) ----

/// Workspace tags for the filter sheet's tag selector — mirrors
/// [workspaceMembersProvider] exactly (same FutureProvider.autoDispose
/// shape, same "no workspace/user yet -> empty list" guard).
final workspaceTagsProvider = FutureProvider.autoDispose<List<Tag>>((ref) async {
  final workspace = ref.watch(workspaceControllerProvider).selected;
  final user = ref.watch(authControllerProvider).user;
  if (workspace == null || user == null) return const [];
  final repository = ref.watch(leadRepositoryProvider);
  return repository.listTags(accessToken: user.accessToken, workspaceId: workspace.workspace.id);
});

final leadFilterStorageProvider = Provider<LeadFilterStorage>((ref) => SecureLeadFilterStorage());

final savedViewsControllerProvider = StateNotifierProvider.autoDispose<SavedViewsController, List<SavedLeadView>>((ref) {
  return SavedViewsController(ref.watch(leadFilterStorageProvider));
});
