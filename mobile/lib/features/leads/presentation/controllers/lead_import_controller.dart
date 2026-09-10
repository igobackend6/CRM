import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/lead_import_state.dart';
import '../../domain/repositories/lead_repository.dart';
import 'csv_file_picker.dart';
import 'lead_request_context.dart';

/// Phase 13's CSV import flow: pick a file, upload its raw text content,
/// show a loading state, then the server's row-level result summary
/// (§"CSV Import"). One instance per import sheet (see
/// leads_providers.dart's `.autoDispose`) — a fresh idle state every
/// time the sheet reopens.
class LeadImportController extends StateNotifier<LeadImportState> {
  LeadImportController(this._repository, this._picker, this._ref) : super(const LeadImportState.idle());

  final LeadRepository _repository;
  final CsvFilePicker _picker;
  final Ref _ref;

  Future<void> pickFile() async {
    try {
      final picked = await _picker.pickCsvFile();
      if (picked == null) return;
      state = const LeadImportState.idle().copyWith(fileName: picked.fileName, csvContent: picked.content);
    } catch (e) {
      AppLogger.warning('Could not read the selected CSV file: $e');
      state = state.copyWith(status: LeadImportStatus.error, errorMessage: 'Could not read the selected file.');
    }
  }

  Future<void> import() async {
    final context = resolveLeadContext(_ref.read);
    final csvContent = state.csvContent;
    if (context == null || csvContent == null) return;

    state = state.copyWith(status: LeadImportStatus.uploading, clearError: true);
    try {
      final result = await _repository.importLeads(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        csvContent: csvContent,
      );
      state = state.copyWith(status: LeadImportStatus.success, result: result);
    } on AppException catch (e) {
      state = state.copyWith(status: LeadImportStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('CSV import failed', error: e);
      state = state.copyWith(status: LeadImportStatus.error, errorMessage: 'Could not import leads.');
    }
  }
}
