import '../../../leads/domain/entities/member_summary.dart';

/// Mirrors the backend's `TeamMemberReportRow` (backend/app/schemas/reports.py).
class TeamMemberReportRow {
  const TeamMemberReportRow({
    required this.member,
    required this.leadsAssigned,
    required this.leadsConverted,
    required this.conversionRate,
    required this.calls,
    required this.connectedCalls,
    required this.talkTimeSeconds,
    required this.completedFollowUps,
    required this.pendingFollowUps,
  });

  factory TeamMemberReportRow.fromJson(Map<String, dynamic> json) => TeamMemberReportRow(
        member: MemberSummary.fromJson(json['member'] as Map<String, dynamic>),
        leadsAssigned: json['leads_assigned'] as int? ?? 0,
        leadsConverted: json['leads_converted'] as int? ?? 0,
        conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0.0,
        calls: json['calls'] as int? ?? 0,
        connectedCalls: json['connected_calls'] as int? ?? 0,
        talkTimeSeconds: json['talk_time_seconds'] as int? ?? 0,
        completedFollowUps: json['completed_follow_ups'] as int? ?? 0,
        pendingFollowUps: json['pending_follow_ups'] as int? ?? 0,
      );

  final MemberSummary member;
  final int leadsAssigned;
  final int leadsConverted;
  final double conversionRate;
  final int calls;
  final int connectedCalls;
  final int talkTimeSeconds;
  final int completedFollowUps;
  final int pendingFollowUps;
}

/// Mirrors the backend's `TeamTotals` (backend/app/schemas/reports.py) —
/// workspace-wide aggregate totals alongside the member rows.
class TeamTotals {
  const TeamTotals({
    required this.leadsAssigned,
    required this.leadsConverted,
    required this.conversionRate,
    required this.calls,
    required this.connectedCalls,
    required this.talkTimeSeconds,
    required this.completedFollowUps,
    required this.pendingFollowUps,
  });

  static const zero = TeamTotals(
    leadsAssigned: 0,
    leadsConverted: 0,
    conversionRate: 0.0,
    calls: 0,
    connectedCalls: 0,
    talkTimeSeconds: 0,
    completedFollowUps: 0,
    pendingFollowUps: 0,
  );

  factory TeamTotals.fromJson(Map<String, dynamic> json) => TeamTotals(
        leadsAssigned: json['leads_assigned'] as int? ?? 0,
        leadsConverted: json['leads_converted'] as int? ?? 0,
        conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0.0,
        calls: json['calls'] as int? ?? 0,
        connectedCalls: json['connected_calls'] as int? ?? 0,
        talkTimeSeconds: json['talk_time_seconds'] as int? ?? 0,
        completedFollowUps: json['completed_follow_ups'] as int? ?? 0,
        pendingFollowUps: json['pending_follow_ups'] as int? ?? 0,
      );

  final int leadsAssigned;
  final int leadsConverted;
  final double conversionRate;
  final int calls;
  final int connectedCalls;
  final int talkTimeSeconds;
  final int completedFollowUps;
  final int pendingFollowUps;
}

/// Mirrors the backend's `TeamReportOut` (backend/app/schemas/reports.py)
/// — one page of `GET /reports/team`'s member rows plus the always-
/// workspace-wide `totals` (never paginated — Phase 21C §"Pagination":
/// "Do not paginate summary KPI values unnecessarily").
class TeamReportPage {
  const TeamReportPage({
    required this.range,
    this.since,
    this.until,
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.totals,
  });

  factory TeamReportPage.fromJson(Map<String, dynamic> json) => TeamReportPage(
        range: json['range'] as String? ?? 'all_time',
        since: json['since'] != null ? DateTime.parse(json['since'] as String) : null,
        until: json['until'] != null ? DateTime.parse(json['until'] as String) : null,
        items: (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(TeamMemberReportRow.fromJson).toList(),
        total: json['total'] as int? ?? 0,
        limit: json['limit'] as int? ?? 20,
        offset: json['offset'] as int? ?? 0,
        totals: TeamTotals.fromJson(json['totals'] as Map<String, dynamic>? ?? const {}),
      );

  final String range;
  final DateTime? since;
  final DateTime? until;
  final List<TeamMemberReportRow> items;
  final int total;
  final int limit;
  final int offset;
  final TeamTotals totals;
}
