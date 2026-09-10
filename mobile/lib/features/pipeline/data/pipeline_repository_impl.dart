import '../../../services/api/pipeline_api_data_source.dart';
import '../../leads/domain/entities/lead.dart';
import '../domain/entities/pipeline_column.dart';
import '../domain/repositories/pipeline_repository.dart';

class PipelineRepositoryImpl implements PipelineRepository {
  PipelineRepositoryImpl(this._dataSource);

  final PipelineApiDataSource _dataSource;

  @override
  Future<List<PipelineColumn>> getPipeline({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? assignedMemberId,
    String? sourceId,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _dataSource.getPipeline(
      accessToken: accessToken,
      workspaceId: workspaceId,
      search: search,
      assignedMemberId: assignedMemberId,
      sourceId: sourceId,
      limit: limit,
      offset: offset,
    );
    return (json['columns'] as List? ?? const []).cast<Map<String, dynamic>>().map(PipelineColumn.fromJson).toList();
  }

  @override
  Future<Lead> changeLeadStatus({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String statusId,
  }) async {
    final json = await _dataSource.changeLeadStatus(
      accessToken: accessToken,
      workspaceId: workspaceId,
      leadId: leadId,
      statusId: statusId,
    );
    return Lead.fromJson(json);
  }
}
