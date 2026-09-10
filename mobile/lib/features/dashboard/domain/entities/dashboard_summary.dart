import 'leads_by_status_item.dart';
import 'team_productivity_row.dart';

/// Mirrors the backend's `DashboardSummaryOut`
/// (backend/app/schemas/dashboard.py) — Phase 11's nine aggregate
/// counts, already scoped to what the caller can see by RLS underneath
/// (a team_mate's counts cover only their own leads/calls/follow-ups, a
/// manager's cover the whole workspace — see that schema's own
/// docstring), plus Phase 17's period/productivity analytics. Same field
/// split as the backend schema: the original 9 fields never change
/// meaning regardless of [range]; everything from [range] down is a
/// period metric computed over the selected window (all-time when
/// `range == 'all'`, the default).
class DashboardSummary {
  const DashboardSummary({
    required this.totalActiveLeads,
    required this.newLeads,
    required this.customers,
    required this.pendingFollowUps,
    required this.overdueFollowUps,
    required this.completedFollowUps,
    required this.totalCalls,
    required this.todaysCalls,
    required this.unreadNotifications,
    this.range = 'all',
    this.leadsCreatedInRange = 0,
    this.convertedLeadsInRange = 0,
    this.conversionRate = 0.0,
    this.callsConnectedInRange = 0,
    this.callsCompletedInRange = 0,
    this.completedFollowUpsInRange = 0,
    this.leadsByStatus = const [],
    this.teamProductivity = const [],
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) => DashboardSummary(
        totalActiveLeads: json['total_active_leads'] as int? ?? 0,
        newLeads: json['new_leads'] as int? ?? 0,
        customers: json['customers'] as int? ?? 0,
        pendingFollowUps: json['pending_follow_ups'] as int? ?? 0,
        overdueFollowUps: json['overdue_follow_ups'] as int? ?? 0,
        completedFollowUps: json['completed_follow_ups'] as int? ?? 0,
        totalCalls: json['total_calls'] as int? ?? 0,
        todaysCalls: json['todays_calls'] as int? ?? 0,
        unreadNotifications: json['unread_notifications'] as int? ?? 0,
        range: json['range'] as String? ?? 'all',
        leadsCreatedInRange: json['leads_created_in_range'] as int? ?? 0,
        convertedLeadsInRange: json['converted_leads_in_range'] as int? ?? 0,
        conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0.0,
        callsConnectedInRange: json['calls_connected_in_range'] as int? ?? 0,
        callsCompletedInRange: json['calls_completed_in_range'] as int? ?? 0,
        completedFollowUpsInRange: json['completed_follow_ups_in_range'] as int? ?? 0,
        leadsByStatus: (json['leads_by_status'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(LeadsByStatusItem.fromJson)
            .toList(),
        teamProductivity: (json['team_productivity'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(TeamProductivityRow.fromJson)
            .toList(),
      );

  // ---- Phase 11 — unchanged ----
  final int totalActiveLeads;
  final int newLeads;
  final int customers;
  final int pendingFollowUps;
  final int overdueFollowUps;
  final int completedFollowUps;
  final int totalCalls;
  final int todaysCalls;
  final int unreadNotifications;

  // ---- Phase 17 — period analytics ----
  final String range;
  final int leadsCreatedInRange;
  final int convertedLeadsInRange;
  final double conversionRate;
  final int callsConnectedInRange;
  final int callsCompletedInRange;
  final int completedFollowUpsInRange;
  final List<LeadsByStatusItem> leadsByStatus;
  final List<TeamProductivityRow> teamProductivity;
}
