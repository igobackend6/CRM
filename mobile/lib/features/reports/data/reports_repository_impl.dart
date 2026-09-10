import '../../../services/api/reports_api_data_source.dart';
import '../domain/entities/personal_report.dart';
import '../domain/entities/pipeline_report.dart';
import '../domain/entities/team_report.dart';
import '../domain/repositories/reports_repository.dart';

class ReportsRepositoryImpl implements ReportsRepository {
  ReportsRepositoryImpl(this._dataSource);

  final ReportsApiDataSource _dataSource;

  @override
  Future<PersonalReport> getPersonalReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  }) async {
    final json = await _dataSource.getPersonalReport(
      accessToken: accessToken,
      workspaceId: workspaceId,
      range: range,
      since: since,
      until: until,
    );
    return PersonalReport.fromJson(json);
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
    final json = await _dataSource.getTeamReport(
      accessToken: accessToken,
      workspaceId: workspaceId,
      range: range,
      since: since,
      until: until,
      limit: limit,
      offset: offset,
    );
    return TeamReportPage.fromJson(json);
  }

  @override
  Future<PipelineReport> getPipelineReport({
    required String accessToken,
    required String workspaceId,
    required String range,
    DateTime? since,
    DateTime? until,
  }) async {
    final json = await _dataSource.getPipelineReport(
      accessToken: accessToken,
      workspaceId: workspaceId,
      range: range,
      since: since,
      until: until,
    );
    return PipelineReport.fromJson(json);
  }
}
