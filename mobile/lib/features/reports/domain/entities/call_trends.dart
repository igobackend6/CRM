/// Which direction of calls the trends chart covers — the Overall/
/// Outbound/Inbound segmented control. `all` is "Overall"; the backend
/// (`GET /reports/call-trends`, `direction` query param) takes the
/// lowercase `apiValue`.
enum CallTrendDirection {
  all,
  outbound,
  inbound;

  String get apiValue => name;

  String get label => switch (this) {
        CallTrendDirection.all => 'Overall',
        CallTrendDirection.outbound => 'Outbound',
        CallTrendDirection.inbound => 'Inbound',
      };
}

/// Bar width of the chart: one bar per `hour` (a single-day window) or per
/// `day` (week/month windows). The backend counts buckets from `since`, so
/// this only decides the step length.
enum CallTrendGranularity {
  hour,
  day;

  String get apiValue => name;
}

/// Mirrors the backend's `CallTrendBucket` (backend/app/schemas/reports.py)
/// — the calls that started in `[start, start + step)`.
class CallTrendBucket {
  const CallTrendBucket({
    required this.start,
    required this.calls,
    required this.uniqueLeads,
    required this.talkTimeSeconds,
  });

  factory CallTrendBucket.fromJson(Map<String, dynamic> json) => CallTrendBucket(
        start: DateTime.parse(json['start'] as String),
        calls: json['calls'] as int? ?? 0,
        uniqueLeads: json['unique_leads'] as int? ?? 0,
        talkTimeSeconds: json['talk_time_seconds'] as int? ?? 0,
      );

  final DateTime start;
  final int calls;
  final int uniqueLeads;
  final int talkTimeSeconds;
}

/// Mirrors the backend's `CallTrendsOut`. `uniqueLeads` is distinct leads
/// across the *whole* window, so it is not the sum of the per-bucket
/// values (a lead called in two buckets counts once here).
class CallTrends {
  const CallTrends({
    required this.granularity,
    required this.buckets,
    required this.totalCalls,
    required this.uniqueLeads,
    required this.totalTalkTimeSeconds,
  });

  static const empty = CallTrends(
    granularity: CallTrendGranularity.day,
    buckets: [],
    totalCalls: 0,
    uniqueLeads: 0,
    totalTalkTimeSeconds: 0,
  );

  factory CallTrends.fromJson(Map<String, dynamic> json) => CallTrends(
        granularity: json['granularity'] == 'hour' ? CallTrendGranularity.hour : CallTrendGranularity.day,
        buckets: (json['buckets'] as List? ?? const []).cast<Map<String, dynamic>>().map(CallTrendBucket.fromJson).toList(),
        totalCalls: json['total_calls'] as int? ?? 0,
        uniqueLeads: json['unique_leads'] as int? ?? 0,
        totalTalkTimeSeconds: json['total_talk_time_seconds'] as int? ?? 0,
      );

  final CallTrendGranularity granularity;
  final List<CallTrendBucket> buckets;
  final int totalCalls;
  final int uniqueLeads;
  final int totalTalkTimeSeconds;
}
