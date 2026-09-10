import '../../../calls/domain/entities/call_outcome.dart';

/// Mirrors the backend's `CallOutcomeBreakdownItem` (backend/app/schemas/reports.py).
class CallOutcomeBreakdownItem {
  const CallOutcomeBreakdownItem({required this.outcome, required this.count});

  factory CallOutcomeBreakdownItem.fromJson(Map<String, dynamic> json) => CallOutcomeBreakdownItem(
        outcome: CallOutcome.fromJson(json['outcome'] as Map<String, dynamic>),
        count: json['count'] as int? ?? 0,
      );

  final CallOutcome outcome;
  final int count;
}

/// Mirrors the backend's `CallMetrics` (backend/app/schemas/reports.py) —
/// Phase 21C's personal/team call-activity breakdown.
class CallMetrics {
  const CallMetrics({
    required this.totalCalls,
    required this.connectedCalls,
    required this.unconnectedCalls,
    required this.completedCalls,
    required this.callsByOutcome,
    required this.totalTalkTimeSeconds,
    required this.averageCallDurationSeconds,
  });

  static const empty = CallMetrics(
    totalCalls: 0,
    connectedCalls: 0,
    unconnectedCalls: 0,
    completedCalls: 0,
    callsByOutcome: [],
    totalTalkTimeSeconds: 0,
    averageCallDurationSeconds: 0.0,
  );

  factory CallMetrics.fromJson(Map<String, dynamic> json) => CallMetrics(
        totalCalls: json['total_calls'] as int? ?? 0,
        connectedCalls: json['connected_calls'] as int? ?? 0,
        unconnectedCalls: json['unconnected_calls'] as int? ?? 0,
        completedCalls: json['completed_calls'] as int? ?? 0,
        callsByOutcome:
            (json['calls_by_outcome'] as List? ?? const []).cast<Map<String, dynamic>>().map(CallOutcomeBreakdownItem.fromJson).toList(),
        totalTalkTimeSeconds: json['total_talk_time_seconds'] as int? ?? 0,
        averageCallDurationSeconds: (json['average_call_duration_seconds'] as num?)?.toDouble() ?? 0.0,
      );

  final int totalCalls;
  final int connectedCalls;
  final int unconnectedCalls;
  final int completedCalls;
  final List<CallOutcomeBreakdownItem> callsByOutcome;
  final int totalTalkTimeSeconds;
  final double averageCallDurationSeconds;
}
