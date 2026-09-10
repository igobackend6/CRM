import '../../../leads/domain/entities/lead_status.dart';

/// Mirrors the backend's `ReportStatusItem` (backend/app/schemas/reports.py)
/// — the personal report's member-scoped pipeline breakdown. Reuses the
/// existing `LeadStatus` entity unchanged, same as the dashboard's
/// `LeadsByStatusItem`.
class ReportStatusItem {
  const ReportStatusItem({required this.status, required this.count});

  factory ReportStatusItem.fromJson(Map<String, dynamic> json) => ReportStatusItem(
        status: LeadStatus.fromJson(json['status'] as Map<String, dynamic>),
        count: json['count'] as int? ?? 0,
      );

  final LeadStatus status;
  final int count;
}
