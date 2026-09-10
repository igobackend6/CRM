import 'call_metrics.dart';
import 'follow_up_metrics.dart';
import 'lead_metrics.dart';
import 'pipeline_snapshot.dart';

/// Mirrors the backend's `PersonalReportOut`
/// (backend/app/schemas/reports.py) — `GET /reports/personal`, always
/// scoped to the calling member.
class PersonalReport {
  const PersonalReport({
    required this.range,
    this.since,
    this.until,
    required this.calls,
    required this.followUps,
    required this.leads,
    required this.pipeline,
  });

  static const empty = PersonalReport(
    range: 'all_time',
    calls: CallMetrics.empty,
    followUps: FollowUpMetrics.empty,
    leads: LeadMetrics.empty,
    pipeline: PipelineSnapshot.empty,
  );

  factory PersonalReport.fromJson(Map<String, dynamic> json) => PersonalReport(
        range: json['range'] as String? ?? 'all_time',
        since: json['since'] != null ? DateTime.parse(json['since'] as String) : null,
        until: json['until'] != null ? DateTime.parse(json['until'] as String) : null,
        calls: CallMetrics.fromJson(json['calls'] as Map<String, dynamic>? ?? const {}),
        followUps: FollowUpMetrics.fromJson(json['follow_ups'] as Map<String, dynamic>? ?? const {}),
        leads: LeadMetrics.fromJson(json['leads'] as Map<String, dynamic>? ?? const {}),
        pipeline: PipelineSnapshot.fromJson(json['pipeline'] as Map<String, dynamic>? ?? const {}),
      );

  final String range;
  final DateTime? since;
  final DateTime? until;
  final CallMetrics calls;
  final FollowUpMetrics followUps;
  final LeadMetrics leads;
  final PipelineSnapshot pipeline;
}
