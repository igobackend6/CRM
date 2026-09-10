import '../../../leads/domain/entities/lead_status.dart';

/// One `lead_statuses` column's lead count — the pipeline distribution
/// KPI (Phase 17 §"Pipeline metrics"). Mirrors the backend's
/// `LeadsByStatusItem` (backend/app/schemas/dashboard.py), reusing the
/// existing `LeadStatus` entity unchanged rather than a slimmer
/// duplicate.
class LeadsByStatusItem {
  const LeadsByStatusItem({required this.status, required this.count});

  factory LeadsByStatusItem.fromJson(Map<String, dynamic> json) => LeadsByStatusItem(
        status: LeadStatus.fromJson(json['status'] as Map<String, dynamic>),
        count: json['count'] as int? ?? 0,
      );

  final LeadStatus status;
  final int count;
}
