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
}
