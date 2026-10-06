import '../entities/call_trends.dart';
import '../entities/personal_report.dart';
import '../entities/pipeline_report.dart';
import '../entities/team_report.dart';

abstract class ReportsRepository {
  Future<PersonalReport> getPersonalReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  });

  Future<TeamReportPage> getTeamReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
    int limit = 20,
    int offset = 0,
  });

  Future<PipelineReport> getPipelineReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  });

  /// The caller's own calls bucketed for the Analytics hub's Call
  /// Analytics chart — `since`/`until` are the instants of the user's
  /// local period boundaries (see `CallAnalyticsPeriod`).
  Future<CallTrends> getCallTrends({
    required String accessToken,
    required String workspaceId,
    required DateTime since,
    required DateTime until,
    required CallTrendGranularity granularity,
    required CallTrendDirection direction,
  });
}
