import '../../../leads/domain/entities/member_summary.dart';
import 'lead_summary.dart';

/// Mirrors the backend's `FollowUpOut` shape (backend/app/schemas/followups.py),
/// itself the enriched form of `follow_ups`
/// (supabase/migrations/000009_calls_followups.sql) — lead/assigned
/// member/created-by are already resolved server-side, not raw ids.
/// Reuses [MemberSummary] from the leads feature rather than defining a
/// second identical type (Phase 7 §6: reuse, don't duplicate).
class FollowUp {
  const FollowUp({
    required this.id,
    required this.workspaceId,
    required this.lead,
    required this.type,
    required this.dueAt,
    required this.status,
    this.notes,
    this.assignedMember,
    this.createdByMember,
    this.completedAt,
    this.cancelledAt,
    this.isOverdue = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FollowUp.fromJson(Map<String, dynamic> json) => FollowUp(
        id: json['id'] as String,
        workspaceId: json['workspace_id'] as String,
        lead: LeadSummary.fromJson(json['lead'] as Map<String, dynamic>),
        type: json['type'] as String,
        dueAt: DateTime.parse(json['due_at'] as String),
        status: json['status'] as String,
        notes: json['notes'] as String?,
        assignedMember:
            json['assigned_member'] != null ? MemberSummary.fromJson(json['assigned_member'] as Map<String, dynamic>) : null,
        createdByMember:
            json['created_by_member'] != null ? MemberSummary.fromJson(json['created_by_member'] as Map<String, dynamic>) : null,
        completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
        cancelledAt: json['cancelled_at'] != null ? DateTime.parse(json['cancelled_at'] as String) : null,
        isOverdue: json['is_overdue'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String workspaceId;
  final LeadSummary lead;
  final String type;
  final DateTime dueAt;
  final String status;
  final String? notes;
  final MemberSummary? assignedMember;
  final MemberSummary? createdByMember;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final bool isOverdue;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == 'pending';
}
