import 'document.dart';

enum DocumentListStatus { initial, loading, refreshing, loadingMore, success, empty, error }

/// Mirrors every other list-with-pagination state in this app
/// (TimelineListState/FollowUpListState/the original, now-retired
/// customer360 DocumentListState). `uploading`/`deletingId` are
/// additive to the base list status — an upload or delete in flight
/// doesn't interrupt whatever the list itself is currently showing.
class DocumentListState {
  const DocumentListState._({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.limit = 20,
    this.errorMessage,
    this.uploading = false,
    this.uploadError,
    this.deletingId,
  });

  const DocumentListState.initial() : this._(status: DocumentListStatus.initial);

  final DocumentListStatus status;
  final List<Document> items;
  final int total;
  final int limit;
  final String? errorMessage;
  final bool uploading;
  final String? uploadError;
  final String? deletingId;

  bool get hasMore => items.length < total;

  DocumentListState copyWith({
    DocumentListStatus? status,
    List<Document>? items,
    int? total,
    String? errorMessage,
    bool clearError = false,
    bool? uploading,
    String? uploadError,
    bool clearUploadError = false,
    String? deletingId,
    bool clearDeletingId = false,
  }) {
    return DocumentListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      limit: limit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      uploading: uploading ?? this.uploading,
      uploadError: clearUploadError ? null : (uploadError ?? this.uploadError),
      deletingId: clearDeletingId ? null : (deletingId ?? this.deletingId),
    );
  }
}
