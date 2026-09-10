import 'report_status_item.dart';

/// Mirrors the backend's `PipelineSnapshot` (backend/app/schemas/reports.py)
/// — the personal report's "my pipeline" slice. `customerCount`/
/// `lostLeads`/`activePipelineCount` are always all-time (not
/// range-windowed) — they describe where a lead sits right now, not how
/// many entered a status during the selected window.
class PipelineSnapshot {
  const PipelineSnapshot({
    required this.leadsByStatus,
    required this.customerCount,
    required this.lostLeads,
    required this.activePipelineCount,
  });

  static const empty = PipelineSnapshot(leadsByStatus: [], customerCount: 0, lostLeads: 0, activePipelineCount: 0);

  factory PipelineSnapshot.fromJson(Map<String, dynamic> json) => PipelineSnapshot(
        leadsByStatus:
            (json['leads_by_status'] as List? ?? const []).cast<Map<String, dynamic>>().map(ReportStatusItem.fromJson).toList(),
        customerCount: json['customer_count'] as int? ?? 0,
        lostLeads: json['lost_leads'] as int? ?? 0,
        activePipelineCount: json['active_pipeline_count'] as int? ?? 0,
      );

  final List<ReportStatusItem> leadsByStatus;
  final int customerCount;
  final int lostLeads;
  final int activePipelineCount;
}
