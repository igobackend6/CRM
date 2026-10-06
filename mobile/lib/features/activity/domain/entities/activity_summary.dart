/// Whether the member is on a break right now, as the backend last
/// reported it (every heartbeat and break action returns this).
class ActivityStatus {
  const ActivityStatus({this.onBreak = false, this.breakStartedAt});

  static const off = ActivityStatus();

  factory ActivityStatus.fromJson(Map<String, dynamic> json) => ActivityStatus(
        onBreak: json['on_break'] as bool? ?? false,
        breakStartedAt: json['break_started_at'] != null ? DateTime.parse(json['break_started_at'] as String) : null,
      );

  final bool onBreak;
  final DateTime? breakStartedAt;
}

/// Mirrors the backend's `ActivitySummaryOut` — the caller's own totals
/// for one window, in whole seconds. Login = talk + ringing + wrap-up +
/// break + idle (see backend/app/services/activity/calc.py for how time is
/// attributed when categories overlap).
class ActivitySummary {
  const ActivitySummary({
    required this.loginSeconds,
    required this.talkSeconds,
    required this.wrapUpSeconds,
    required this.breakSeconds,
    required this.idleSeconds,
    this.status = ActivityStatus.off,
  });

  static const empty = ActivitySummary(loginSeconds: 0, talkSeconds: 0, wrapUpSeconds: 0, breakSeconds: 0, idleSeconds: 0);

  factory ActivitySummary.fromJson(Map<String, dynamic> json) => ActivitySummary(
        loginSeconds: json['login_seconds'] as int? ?? 0,
        talkSeconds: json['talk_seconds'] as int? ?? 0,
        wrapUpSeconds: json['wrap_up_seconds'] as int? ?? 0,
        breakSeconds: json['break_seconds'] as int? ?? 0,
        idleSeconds: json['idle_seconds'] as int? ?? 0,
        status: ActivityStatus.fromJson(json),
      );

  final int loginSeconds;
  final int talkSeconds;
  final int wrapUpSeconds;
  final int breakSeconds;
  final int idleSeconds;
  final ActivityStatus status;
}
