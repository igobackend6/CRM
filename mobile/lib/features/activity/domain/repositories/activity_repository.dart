import '../entities/activity_summary.dart';

abstract class ActivityRepository {
  /// The running app checking in. [utcOffsetMinutes] is the device's
  /// current UTC offset (India = 330): the schema stores no per-user
  /// timezone, so the backend needs it to know which local day this is.
  Future<ActivityStatus> heartbeat({required String accessToken, required String workspaceId, required int utcOffsetMinutes});

  /// Ends the session (and any break) right now.
  Future<void> signOut({required String accessToken, required String workspaceId, required int utcOffsetMinutes});

  Future<ActivityStatus> startBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes});

  Future<ActivityStatus> endBreak({required String accessToken, required String workspaceId, required int utcOffsetMinutes});

  Future<ActivitySummary> getSummary({
    required String accessToken,
    required String workspaceId,
    required DateTime since,
    required DateTime until,
  });
}
