/// Mirrors the backend's `BulkLeadActionResponse`
/// (backend/app/schemas/data_ops.py) — per-lead success/failure so the
/// UI can show "N of M updated" rather than a single opaque pass/fail
/// (Phase 13 §"return per-lead success/failure information when
/// practical").
class BulkLeadItemResult {
  const BulkLeadItemResult({required this.leadId, required this.success, this.error});

  factory BulkLeadItemResult.fromJson(Map<String, dynamic> json) => BulkLeadItemResult(
        leadId: json['lead_id'] as String,
        success: json['success'] as bool? ?? false,
        error: json['error'] as String?,
      );

  final String leadId;
  final bool success;
  final String? error;
}

class BulkActionResult {
  const BulkActionResult({required this.total, required this.succeeded, required this.failed, required this.items});

  factory BulkActionResult.fromJson(Map<String, dynamic> json) => BulkActionResult(
        total: json['total'] as int? ?? 0,
        succeeded: json['succeeded'] as int? ?? 0,
        failed: json['failed'] as int? ?? 0,
        items: (json['results'] as List? ?? const []).cast<Map<String, dynamic>>().map(BulkLeadItemResult.fromJson).toList(),
      );

  final int total;
  final int succeeded;
  final int failed;
  final List<BulkLeadItemResult> items;
}
