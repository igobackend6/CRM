import 'package:mobile/features/leads/domain/entities/lead_source.dart';
import 'package:mobile/features/leads/domain/entities/lead_status.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/reports/domain/entities/call_metrics.dart';
import 'package:mobile/features/reports/domain/entities/follow_up_metrics.dart';
import 'package:mobile/features/reports/domain/entities/lead_metrics.dart';
import 'package:mobile/features/reports/domain/entities/personal_report.dart';
import 'package:mobile/features/reports/domain/entities/pipeline_report.dart';
import 'package:mobile/features/reports/domain/entities/pipeline_snapshot.dart';
import 'package:mobile/features/reports/domain/entities/report_status_item.dart';
import 'package:mobile/features/reports/domain/entities/team_report.dart';
import 'package:mobile/features/reports/domain/repositories/reports_repository.dart';

LeadStatus testStatus({String id = 's1', String name = 'New', String stage = 'in_progress'}) =>
    LeadStatus(id: id, name: name, code: name.toLowerCase(), sortOrder: 10, stage: stage, isDefault: true);

LeadSource testSource({String id = 'src1', String name = 'Website'}) =>
    LeadSource(id: id, name: name, code: name.toLowerCase(), isDefault: false);

PersonalReport testPersonalReport({
  int totalCalls = 10,
  int leadsAssigned = 5,
  int leadsConverted = 2,
  double conversionRate = 0.4,
}) =>
    PersonalReport(
      range: 'all_time',
      calls: CallMetrics(
        totalCalls: totalCalls,
        connectedCalls: 6,
        unconnectedCalls: 4,
        completedCalls: 6,
        callsByOutcome: const [],
        totalTalkTimeSeconds: 600,
        averageCallDurationSeconds: 100.0,
      ),
      followUps: const FollowUpMetrics(totalFollowUps: 3, pendingFollowUps: 1, completedFollowUps: 2, cancelledFollowUps: 0, overdueFollowUps: 0),
      leads: LeadMetrics(leadsCreated: 4, leadsAssigned: leadsAssigned, leadsContacted: 3, leadsConverted: leadsConverted, conversionRate: conversionRate),
      pipeline: PipelineSnapshot(
        leadsByStatus: [ReportStatusItem(status: testStatus(), count: 2)],
        customerCount: 2,
        lostLeads: 1,
        activePipelineCount: 2,
      ),
    );

TeamMemberReportRow testTeamRow({String memberId = 'm1', String fullName = 'Jamie Rep', int leadsConverted = 1}) => TeamMemberReportRow(
      member: MemberSummary(id: memberId, fullName: fullName),
      leadsAssigned: 3,
      leadsConverted: leadsConverted,
      conversionRate: leadsConverted / 3,
      calls: 5,
      connectedCalls: 3,
      talkTimeSeconds: 300,
      completedFollowUps: 2,
      pendingFollowUps: 1,
    );

TeamReportPage testTeamReportPage({List<TeamMemberReportRow> items = const [], int total = 0, int limit = 20, int offset = 0}) =>
    TeamReportPage(
      range: 'all_time',
      items: items,
      total: total,
      limit: limit,
      offset: offset,
      totals: TeamTotals(
        leadsAssigned: items.fold(0, (a, r) => a + r.leadsAssigned),
        leadsConverted: items.fold(0, (a, r) => a + r.leadsConverted),
        conversionRate: 0.5,
        calls: items.fold(0, (a, r) => a + r.calls),
        connectedCalls: items.fold(0, (a, r) => a + r.connectedCalls),
        talkTimeSeconds: items.fold(0, (a, r) => a + r.talkTimeSeconds),
        completedFollowUps: items.fold(0, (a, r) => a + r.completedFollowUps),
        pendingFollowUps: items.fold(0, (a, r) => a + r.pendingFollowUps),
      ),
    );

PipelineReport testPipelineReport() => PipelineReport(
      range: 'all_time',
      leadsByStatus: [PipelineStatusItem(status: testStatus(), count: 5, percentage: 100.0)],
      convertedCustomers: 3,
      lostLeads: 1,
      activeLeads: 4,
      sourcePerformance: [PipelineSourceItem(source: testSource(), leadsCount: 5, convertedCount: 2, conversionRate: 0.4)],
      priorityDistribution: const [
        PipelinePriorityItem(priority: 'low', count: 1, percentage: 25.0),
        PipelinePriorityItem(priority: 'medium', count: 2, percentage: 50.0),
        PipelinePriorityItem(priority: 'high', count: 1, percentage: 25.0),
        PipelinePriorityItem(priority: 'urgent', count: 0, percentage: 0.0),
      ],
    );

class FakeReportsRepository implements ReportsRepository {
  PersonalReport personalReportToReturn = testPersonalReport();
  Object? personalError;

  TeamReportPage teamReportToReturn = testTeamReportPage();
  Object? teamError;

  PipelineReport pipelineReportToReturn = testPipelineReport();
  Object? pipelineError;

  String? lastRange;
  int? lastTeamOffset;
  int callCount = 0;

  @override
  Future<PersonalReport> getPersonalReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  }) async {
    callCount++;
    lastRange = range;
    if (personalError != null) throw personalError!;
    return personalReportToReturn;
  }

  @override
  Future<TeamReportPage> getTeamReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
    int limit = 20,
    int offset = 0,
  }) async {
    callCount++;
    lastRange = range;
    lastTeamOffset = offset;
    if (teamError != null) throw teamError!;
    return TeamReportPage(
      range: teamReportToReturn.range,
      items: teamReportToReturn.items,
      total: teamReportToReturn.total,
      limit: limit,
      offset: offset,
      totals: teamReportToReturn.totals,
    );
  }

  @override
  Future<PipelineReport> getPipelineReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  }) async {
    callCount++;
    lastRange = range;
    if (pipelineError != null) throw pipelineError!;
    return pipelineReportToReturn;
  }
}
