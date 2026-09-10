import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/external_url_launcher.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../data/document_file_picker.dart';
import '../../domain/entities/document_list_state.dart';
import '../../domain/repositories/document_repository.dart';

/// One instance per lead (`.family`) — Secure Lead Documents (§2/§3),
/// shared by both Lead Detail and Customer 360 (a customer IS a lead —
/// see leads' own `is_customer` model), so there is exactly one
/// document-management UI/controller, not two (§4 "Do not create a
/// second document-management UI").
class DocumentListController extends StateNotifier<DocumentListState> {
  DocumentListController(this._repository, this._ref, this.leadId, {DocumentFilePicker? filePicker, ExternalUrlLauncher? launcher})
      : _filePicker = filePicker ?? FilePickerDocumentFilePicker(),
        _launcher = launcher ?? DefaultExternalUrlLauncher(),
        super(const DocumentListState.initial());

  final DocumentRepository _repository;
  final Ref _ref;
  final String leadId;
  final DocumentFilePicker _filePicker;
  final ExternalUrlLauncher _launcher;

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final isFirstLoad = state.status == DocumentListStatus.initial;
    state = state.copyWith(status: isFirstLoad ? DocumentListStatus.loading : DocumentListStatus.refreshing, clearError: true);

    try {
      final page = await _repository.listDocuments(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        limit: state.limit,
        offset: 0,
      );
      state = state.copyWith(
        status: page.items.isEmpty ? DocumentListStatus.empty : DocumentListStatus.success,
        items: page.items,
        total: page.total,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(status: DocumentListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load documents for lead $leadId', error: e);
      state = state.copyWith(status: DocumentListStatus.error, errorMessage: 'Could not load documents.');
    }
  }

  Future<void> loadMore() async {
    if (state.status == DocumentListStatus.loadingMore || !state.hasMore) return;
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: DocumentListStatus.loadingMore);
    try {
      final page = await _repository.listDocuments(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        limit: state.limit,
        offset: state.items.length,
      );
      state = state.copyWith(status: DocumentListStatus.success, items: [...state.items, ...page.items], total: page.total);
    } on AppException catch (e) {
      state = state.copyWith(status: DocumentListStatus.success, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load more documents for lead $leadId', error: e);
      state = state.copyWith(status: DocumentListStatus.success, errorMessage: 'Could not load more documents.');
    }
  }

  /// Opens the file picker and, if the user picked something, uploads
  /// it — client-side rejection (`AppException`/`ValidationException`
  /// for a disallowed type/size) surfaces the same way a server 422
  /// does, since DocumentService re-validates everything server-side
  /// regardless (§"Security" — the server is the real gate, this is
  /// just faster feedback).
  Future<void> pickAndUpload() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    final picked = await _filePicker.pickDocumentFile();
    if (picked == null) return;

    state = state.copyWith(uploading: true, clearUploadError: true);
    try {
      final document = await _repository.uploadDocument(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        file: picked,
      );
      state = state.copyWith(
        status: DocumentListStatus.success,
        items: [document, ...state.items],
        total: state.total + 1,
        uploading: false,
      );
    } on AppException catch (e) {
      state = state.copyWith(uploading: false, uploadError: e.message);
    } catch (e) {
      AppLogger.error('Failed to upload document for lead $leadId', error: e);
      state = state.copyWith(uploading: false, uploadError: 'Could not upload the file. Please try again.');
    }
  }

  /// Preview/Download (§3) — both are "open this signed URL"; the
  /// difference is purely how the OS/browser presents the result for
  /// that file type, not something this app decides.
  Future<bool> openDocument(String documentId) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return false;
    try {
      final url = await _repository.getSignedUrl(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        documentId: documentId,
      );
      return _launcher.launch(Uri.parse(url));
    } on AppException catch (e) {
      AppLogger.error('Failed to get signed URL for document $documentId', error: e);
      return false;
    }
  }

  Future<void> deleteDocument(String documentId) async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(deletingId: documentId);
    try {
      await _repository.deleteDocument(
        accessToken: context.accessToken,
        workspaceId: context.workspaceId,
        leadId: leadId,
        documentId: documentId,
      );
      final remaining = state.items.where((d) => d.id != documentId).toList();
      state = state.copyWith(
        status: remaining.isEmpty ? DocumentListStatus.empty : DocumentListStatus.success,
        items: remaining,
        total: state.total - 1,
        clearDeletingId: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(clearDeletingId: true, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to delete document $documentId', error: e);
      state = state.copyWith(clearDeletingId: true, errorMessage: 'Could not delete the document.');
    }
  }
}
