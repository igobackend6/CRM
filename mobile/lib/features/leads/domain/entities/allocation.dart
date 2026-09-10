import 'member_summary.dart';

/// One entry of a lead's read-only assignment history — mirrors the
/// backend's `AllocationOut` (backend/app/schemas/assignment.py), itself
/// built from `allocations` (supabase/migrations/000010_allocations_interactions.sql)
/// plus a server-computed `previous_member` (not a stored column).
class Allocation {
  const Allocation({
    required this.id,
    this.previousMember,
    this.assignedMember,
    this.assignedBy,
    required this.status,
    required this.assignedAt,
    required this.createdAt,
  });

  factory Allocation.fromJson(Map<String, dynamic> json) => Allocation(
        id: json['id'] as String,
        previousMember:
            json['previous_member'] != null ? MemberSummary.fromJson(json['previous_member'] as Map<String, dynamic>) : null,
        assignedMember:
            json['assigned_member'] != null ? MemberSummary.fromJson(json['assigned_member'] as Map<String, dynamic>) : null,
        assignedBy: json['assigned_by'] != null ? MemberSummary.fromJson(json['assigned_by'] as Map<String, dynamic>) : null,
        status: json['status'] as String,
        assignedAt: DateTime.parse(json['assigned_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final MemberSummary? previousMember;
  final MemberSummary? assignedMember;
  final MemberSummary? assignedBy;
  final String status;
  final DateTime assignedAt;
  final DateTime createdAt;
}
