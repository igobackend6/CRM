import '../../../leads/domain/entities/lead_status.dart';
import '../../../leads/domain/entities/member_summary.dart';
import 'rechurn_next_follow_up.dart';

/// One Rechurn queue row (Phase 19) — mirrors the backend's
/// `RechurnLeadCard` (backend/app/schemas/rechurn.py). A rechurn
/// candidate is still just a lead (the same `leads.id` space Lead
/// Detail/Customer 360/Pipeline already use) — never a second record.
class RechurnLeadCard {
  const RechurnLeadCard({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    required this.priority,
    this.status,
    this.assignedMember,
    required this.isCustomer,
    required this.lastActivityAt,
    this.nextFollowUp,
  });

  factory RechurnLeadCard.fromJson(Map<String, dynamic> json) => RechurnLeadCard(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        priority: json['priority'] as String? ?? 'medium',
        status: json['status'] != null ? LeadStatus.fromJson(json['status'] as Map<String, dynamic>) : null,
        assignedMember:
            json['assigned_member'] != null ? MemberSummary.fromJson(json['assigned_member'] as Map<String, dynamic>) : null,
        isCustomer: json['is_customer'] as bool? ?? false,
        lastActivityAt: DateTime.parse(json['last_activity_at'] as String),
        nextFollowUp: json['next_follow_up'] != null
            ? RechurnNextFollowUp.fromJson(json['next_follow_up'] as Map<String, dynamic>)
            : null,
      );

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String priority;
  final LeadStatus? status;
  final MemberSummary? assignedMember;
  final bool isCustomer;
  final DateTime lastActivityAt;
  final RechurnNextFollowUp? nextFollowUp;

  /// Reflects a server-confirmed status change in place (Phase 19's
  /// inline "Update status" action) — mirrors `Lead.copyWithTags`'s
  /// shape, so the queue row updates without a full re-fetch.
  RechurnLeadCard copyWithStatus(LeadStatus newStatus) => RechurnLeadCard(
        id: id,
        name: name,
        phone: phone,
        email: email,
        priority: priority,
        status: newStatus,
        assignedMember: assignedMember,
        isCustomer: isCustomer,
        lastActivityAt: lastActivityAt,
        nextFollowUp: nextFollowUp,
      );
}
