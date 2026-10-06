import '../../../services/api/activity_api_data_source.dart';
import '../domain/entities/activity_summary.dart';
import '../domain/repositories/activity_repository.dart';

class ActivityRepositoryImpl implements ActivityRepository {
  ActivityRepositoryImpl(this._dataSource);

  final ActivityApiDataSource _dataSource;

  @override
  Future<ActivityStatus> heartbeat({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) async {
    final json = await _dataSource.heartbeat(accessToken: accessToken, workspaceId: workspaceId, utcOffsetMinutes: utcOffsetMinutes);
    return ActivityStatus.fromJson(json);
  }

  @override
  Future<void> signOut({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) async {
    await _dataSource.signOut(accessToken: accessToken, workspaceId: workspaceId, utcOffsetMinutes: utcOffsetMinutes);
  }

  @override
  Future<ActivityStatus> startBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) async {
    final json = await _dataSource.startBreak(accessToken: accessToken, workspaceId: workspaceId, utcOffsetMinutes: utcOffsetMinutes);
    return ActivityStatus.fromJson(json);
  }

  @override
  Future<ActivityStatus> endBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) async {
    final json = await _dataSource.endBreak(accessToken: accessToken, workspaceId: workspaceId, utcOffsetMinutes: utcOffsetMinutes);
    return ActivityStatus.fromJson(json);
  }

  @override
  Future<ActivitySummary> getSummary({
    required String accessToken,
    required String workspaceId,
    required DateTime since,
    required DateTime until,
  }) async {
    final json = await _dataSource.getSummary(accessToken: accessToken, workspaceId: workspaceId, since: since, until: until);
    return ActivitySummary.fromJson(json);
  }
}
