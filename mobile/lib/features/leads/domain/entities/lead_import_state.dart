/// Mirrors the backend's `LeadImportResponse`
/// (backend/app/schemas/data_ops.py).
class LeadImportRowError {
  const LeadImportRowError({required this.row, required this.error});

  factory LeadImportRowError.fromJson(Map<String, dynamic> json) =>
      LeadImportRowError(row: json['row'] as int, error: json['error'] as String);

  final int row;
  final String error;
}

class LeadImportResult {
  const LeadImportResult({required this.total, required this.created, required this.failed, required this.errors});

  factory LeadImportResult.fromJson(Map<String, dynamic> json) => LeadImportResult(
        total: json['total'] as int? ?? 0,
        created: json['created'] as int? ?? 0,
        failed: json['failed'] as int? ?? 0,
        errors: (json['errors'] as List? ?? const []).cast<Map<String, dynamic>>().map(LeadImportRowError.fromJson).toList(),
      );

  final int total;
  final int created;
  final int failed;
  final List<LeadImportRowError> errors;
}

enum LeadImportStatus { idle, uploading, success, error }

/// Phase 13's CSV import flow state: idle (nothing picked yet, or a file
/// picked and ready) -> uploading -> success (server's row-level
/// summary) or error.
class LeadImportState {
  const LeadImportState._({required this.status, this.fileName, this.csvContent, this.result, this.errorMessage});

  const LeadImportState.idle() : this._(status: LeadImportStatus.idle);

  final LeadImportStatus status;
  final String? fileName;
  final String? csvContent;
  final LeadImportResult? result;
  final String? errorMessage;

  LeadImportState copyWith({
    LeadImportStatus? status,
    String? fileName,
    String? csvContent,
    LeadImportResult? result,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LeadImportState._(
      status: status ?? this.status,
      fileName: fileName ?? this.fileName,
      csvContent: csvContent ?? this.csvContent,
      result: result ?? this.result,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
