import '../../../leads/domain/entities/lead_status.dart';
import '../../../leads/domain/entities/member_summary.dart';

/// Mirrors the backend's `PipelineLeadCard` shape
/// (backend/app/schemas/pipeline.py) — deliberately narrower than the
/// full `Lead` entity (no tags/source/created_by/is_customer): a
/// pipeline board renders many of these at once, so only what a card
/// actually shows is fetched.
class PipelineLeadCard {
  const PipelineLeadCard({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    required this.priority,
    this.status,
    this.assignedMember,
    required this.updatedAt,
  });

  factory PipelineLeadCard.fromJson(Map<String, dynamic> json) => PipelineLeadCard(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        priority: json['priority'] as String? ?? 'medium',
        status: json['status'] != null ? LeadStatus.fromJson(json['status'] as Map<String, dynamic>) : null,
        assignedMember:
            json['assigned_member'] != null ? MemberSummary.fromJson(json['assigned_member'] as Map<String, dynamic>) : null,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String priority;
  final LeadStatus? status;
  final MemberSummary? assignedMember;
  final DateTime updatedAt;
}
