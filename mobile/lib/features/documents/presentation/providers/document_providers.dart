import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/external_url_launcher.dart';
import '../../../../services/api/document_api_data_source.dart';
import '../../data/document_file_picker.dart';
import '../../data/document_repository_impl.dart';
import '../../domain/entities/document_list_state.dart';
import '../../domain/repositories/document_repository.dart';
import '../controllers/document_list_controller.dart';

final documentApiDataSourceProvider = Provider<DocumentApiDataSource>((ref) => DioDocumentApiDataSource());

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepositoryImpl(ref.watch(documentApiDataSourceProvider));
});

/// Provider seams (rather than constructor defaults alone) for the two
/// plugin-backed collaborators DocumentListController needs — so tests
/// can override them the same way every other feature's providers are
/// overridden in a ProviderContainer/ProviderScope, without needing a
/// real `Ref` to construct the controller directly.
final documentFilePickerProvider = Provider<DocumentFilePicker>((ref) => FilePickerDocumentFilePicker());

final documentExternalUrlLauncherProvider = Provider<ExternalUrlLauncher>((ref) => DefaultExternalUrlLauncher());

/// One controller per lead id — used identically from Lead Detail and
/// Customer 360 (customerId IS a leadId).
final documentListControllerProvider =
    StateNotifierProvider.autoDispose.family<DocumentListController, DocumentListState, String>((ref, leadId) {
  return DocumentListController(
    ref.watch(documentRepositoryProvider),
    ref,
    leadId,
    filePicker: ref.watch(documentFilePickerProvider),
    launcher: ref.watch(documentExternalUrlLauncherProvider),
  );
});
