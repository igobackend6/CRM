import 'package:mobile/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:mobile/features/dashboard/domain/entities/leads_by_status_item.dart';
import 'package:mobile/features/dashboard/domain/entities/recent_activity_item.dart';
import 'package:mobile/features/dashboard/domain/entities/recent_activity_page.dart';
import 'package:mobile/features/dashboard/domain/entities/team_productivity_row.dart';
import 'package:mobile/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';

DashboardSummary testSummary({
  int totalActiveLeads = 4,
  int newLeads = 1,
  int customers = 2,
  int pendingFollowUps = 3,
  int overdueFollowUps = 1,
  int completedFollowUps = 5,
  int totalCalls = 10,
  int todaysCalls = 2,
  int unreadNotifications = 1,
  String range = 'all',
  int leadsCreatedInRange = 0,
  int convertedLeadsInRange = 0,
  double conversionRate = 0.0,
  int callsConnectedInRange = 0,
  int callsCompletedInRange = 0,
  int completedFollowUpsInRange = 0,
  List<LeadsByStatusItem> leadsByStatus = const [],
  List<TeamProductivityRow> teamProductivity = const [],
}) =>
    DashboardSummary(
      totalActiveLeads: totalActiveLeads,
      newLeads: newLeads,
      customers: customers,
      pendingFollowUps: pendingFollowUps,
      overdueFollowUps: overdueFollowUps,
      completedFollowUps: completedFollowUps,
      totalCalls: totalCalls,
      todaysCalls: todaysCalls,
      unreadNotifications: unreadNotifications,
      range: range,
      leadsCreatedInRange: leadsCreatedInRange,
      convertedLeadsInRange: convertedLeadsInRange,
      conversionRate: conversionRate,
      callsConnectedInRange: callsConnectedInRange,
      callsCompletedInRange: callsCompletedInRange,
      completedFollowUpsInRange: completedFollowUpsInRange,
      leadsByStatus: leadsByStatus,
      teamProductivity: teamProductivity,
    );

RecentActivityItem testActivityItem({
  String id = 'call:call-1',
  String type = 'call',
  DateTime? occurredAt,
  MemberSummary? actorMember,
  String summary = 'Outbound call — ended',
}) =>
    RecentActivityItem(
      id: id,
      type: type,
      occurredAt: occurredAt ?? DateTime.utc(2026, 1, 1, 9, 0),
      actorMember: actorMember ?? const MemberSummary(id: 'm1', fullName: 'Rep One'),
      summary: summary,
      details: const {},
    );

class FakeDashboardRepository implements DashboardRepository {
  DashboardSummary summaryToReturn = testSummary();
  Object? summaryError;

  List<RecentActivityItem> activityItemsToReturn = [];
  int activityTotalToReturn = 0;
  Object? activityError;

  int? lastOffset;
  String? lastRange;

  @override
  Future<DashboardSummary> getSummary({required String accessToken, required String workspaceId, String range = 'all'}) async {
    if (summaryError != null) throw summaryError!;
    lastRange = range;
    return summaryToReturn;
  }

  @override
  Future<RecentActivityPage> getRecentActivity({
    required String accessToken,
    required String workspaceId,
    int limit = 10,
    int offset = 0,
  }) async {
    if (activityError != null) throw activityError!;
    lastOffset = offset;
    return RecentActivityPage(items: activityItemsToReturn, total: activityTotalToReturn, limit: limit, offset: offset);
  }
}
