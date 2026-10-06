import 'package:mobile/features/activity/domain/entities/activity_summary.dart';
import 'package:mobile/features/activity/domain/repositories/activity_repository.dart';

/// One recorded call to the fake, so a test can assert what the app sent.
class ActivityCall {
  const ActivityCall(this.kind, this.accessToken, this.workspaceId, this.utcOffsetMinutes);

  final String kind;
  final String accessToken;
  final String workspaceId;
  final int utcOffsetMinutes;
}

class FakeActivityRepository implements ActivityRepository {
  /// What heartbeat / startBreak / endBreak answer with.
  ActivityStatus heartbeatStatus = ActivityStatus.off;
  ActivityStatus startBreakStatus = ActivityStatus(onBreak: true, breakStartedAt: DateTime.utc(2026, 9, 24, 8, 30));
  ActivityStatus endBreakStatus = ActivityStatus.off;

  ActivitySummary summaryToReturn = const ActivitySummary(
    loginSeconds: 254,
    talkSeconds: 60,
    wrapUpSeconds: 30,
    breakSeconds: 0,
    idleSeconds: 164,
  );

  Object? heartbeatError;
  Object? signOutError;
  Object? breakError;
  Object? summaryError;

  final List<ActivityCall> calls = [];
  int summaryCallCount = 0;
  DateTime? lastSince;
  DateTime? lastUntil;

  Iterable<ActivityCall> of(String kind) => calls.where((c) => c.kind == kind);
  int count(String kind) => of(kind).length;

  @override
  Future<ActivityStatus> heartbeat({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) async {
    calls.add(ActivityCall('heartbeat', accessToken, workspaceId, utcOffsetMinutes));
    if (heartbeatError != null) throw heartbeatError!;
    return heartbeatStatus;
  }

  @override
  Future<void> signOut({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) async {
    calls.add(ActivityCall('signOut', accessToken, workspaceId, utcOffsetMinutes));
    if (signOutError != null) throw signOutError!;
  }

  @override
  Future<ActivityStatus> startBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) async {
    calls.add(ActivityCall('startBreak', accessToken, workspaceId, utcOffsetMinutes));
    if (breakError != null) throw breakError!;
    return startBreakStatus;
  }

  @override
  Future<ActivityStatus> endBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes}) async {
    calls.add(ActivityCall('endBreak', accessToken, workspaceId, utcOffsetMinutes));
    if (breakError != null) throw breakError!;
    return endBreakStatus;
  }

  @override
  Future<ActivitySummary> getSummary({
    required String accessToken,
    required String workspaceId,
    required DateTime since,
    required DateTime until,
  }) async {
    summaryCallCount++;
    lastSince = since;
    lastUntil = until;
    if (summaryError != null) throw summaryError!;
    return summaryToReturn;
  }
}
