/// Mirrors the backend's `FollowUpMetrics` (backend/app/schemas/reports.py).
class FollowUpMetrics {
  const FollowUpMetrics({
    required this.totalFollowUps,
    required this.pendingFollowUps,
    required this.completedFollowUps,
    required this.cancelledFollowUps,
    required this.overdueFollowUps,
  });

  static const empty = FollowUpMetrics(
    totalFollowUps: 0,
    pendingFollowUps: 0,
    completedFollowUps: 0,
    cancelledFollowUps: 0,
    overdueFollowUps: 0,
  );

  factory FollowUpMetrics.fromJson(Map<String, dynamic> json) => FollowUpMetrics(
        totalFollowUps: json['total_follow_ups'] as int? ?? 0,
        pendingFollowUps: json['pending_follow_ups'] as int? ?? 0,
        completedFollowUps: json['completed_follow_ups'] as int? ?? 0,
        cancelledFollowUps: json['cancelled_follow_ups'] as int? ?? 0,
        overdueFollowUps: json['overdue_follow_ups'] as int? ?? 0,
      );

  final int totalFollowUps;
  final int pendingFollowUps;
  final int completedFollowUps;
  final int cancelledFollowUps;
  final int overdueFollowUps;
}
