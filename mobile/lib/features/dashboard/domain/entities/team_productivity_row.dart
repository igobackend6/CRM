import '../../../leads/domain/entities/member_summary.dart';

/// One member's productivity row (Phase 17 §"Team productivity") —
/// mirrors the backend's `TeamProductivityRow`
/// (backend/app/schemas/dashboard.py). The backend only ever includes a
/// member here when at least one count is nonzero (see that schema's own
/// docstring on why — RLS already means a team_mate's request only ever
/// sees nonzero counts for themselves), so this entity never needs its
/// own "is this row visible to me" logic.
class TeamProductivityRow {
  const TeamProductivityRow({
    required this.member,
    required this.leadsCount,
    required this.callsCount,
    required this.completedFollowUpsCount,
  });

  factory TeamProductivityRow.fromJson(Map<String, dynamic> json) => TeamProductivityRow(
        member: MemberSummary.fromJson(json['member'] as Map<String, dynamic>),
        leadsCount: json['leads_count'] as int? ?? 0,
        callsCount: json['calls_count'] as int? ?? 0,
        completedFollowUpsCount: json['completed_follow_ups_count'] as int? ?? 0,
      );

  final MemberSummary member;
  final int leadsCount;
  final int callsCount;
  final int completedFollowUpsCount;
}
