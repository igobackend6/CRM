import '../../../leads/domain/entities/lead_source.dart';
import '../../../leads/domain/entities/lead_status.dart';

/// Mirrors the backend's `PipelineStatusItem` (backend/app/schemas/reports.py).
class PipelineStatusItem {
  const PipelineStatusItem({required this.status, required this.count, required this.percentage});

  factory PipelineStatusItem.fromJson(Map<String, dynamic> json) => PipelineStatusItem(
        status: LeadStatus.fromJson(json['status'] as Map<String, dynamic>),
        count: json['count'] as int? ?? 0,
        percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      );

  final LeadStatus status;
  final int count;
  final double percentage;
}

/// Mirrors the backend's `PipelineSourceItem` (backend/app/schemas/reports.py).
class PipelineSourceItem {
  const PipelineSourceItem({required this.source, required this.leadsCount, required this.convertedCount, required this.conversionRate});

  factory PipelineSourceItem.fromJson(Map<String, dynamic> json) => PipelineSourceItem(
        source: LeadSource.fromJson(json['source'] as Map<String, dynamic>),
        leadsCount: json['leads_count'] as int? ?? 0,
        convertedCount: json['converted_count'] as int? ?? 0,
        conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0.0,
      );

  final LeadSource source;
  final int leadsCount;
  final int convertedCount;
  final double conversionRate;
}

/// Mirrors the backend's `PipelinePriorityItem` (backend/app/schemas/reports.py).
/// `priority` is one of the schema's fixed check-constraint values
/// (low/medium/high/urgent — not workspace-configurable, unlike lead
/// statuses/sources), so this carries the raw string, same as `Lead.priority`
/// elsewhere in this app.
class PipelinePriorityItem {
  const PipelinePriorityItem({required this.priority, required this.count, required this.percentage});

  factory PipelinePriorityItem.fromJson(Map<String, dynamic> json) => PipelinePriorityItem(
        priority: json['priority'] as String? ?? '',
        count: json['count'] as int? ?? 0,
        percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      );

  final String priority;
  final int count;
  final double percentage;
}

/// Mirrors the backend's `PipelineReportOut` (backend/app/schemas/reports.py)
/// — `GET /reports/pipeline`, workspace-wide (manager/admin/ceo only).
class PipelineReport {
  const PipelineReport({
    required this.range,
    this.since,
    this.until,
    required this.leadsByStatus,
    required this.convertedCustomers,
    required this.lostLeads,
    required this.activeLeads,
    required this.sourcePerformance,
    required this.priorityDistribution,
  });

  static const empty = PipelineReport(
    range: 'all_time',
    leadsByStatus: [],
    convertedCustomers: 0,
    lostLeads: 0,
    activeLeads: 0,
    sourcePerformance: [],
    priorityDistribution: [],
  );

  factory PipelineReport.fromJson(Map<String, dynamic> json) => PipelineReport(
        range: json['range'] as String? ?? 'all_time',
        since: json['since'] != null ? DateTime.parse(json['since'] as String) : null,
        until: json['until'] != null ? DateTime.parse(json['until'] as String) : null,
        leadsByStatus:
            (json['leads_by_status'] as List? ?? const []).cast<Map<String, dynamic>>().map(PipelineStatusItem.fromJson).toList(),
        convertedCustomers: json['converted_customers'] as int? ?? 0,
        lostLeads: json['lost_leads'] as int? ?? 0,
        activeLeads: json['active_leads'] as int? ?? 0,
        sourcePerformance:
            (json['source_performance'] as List? ?? const []).cast<Map<String, dynamic>>().map(PipelineSourceItem.fromJson).toList(),
        priorityDistribution: (json['priority_distribution'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PipelinePriorityItem.fromJson)
            .toList(),
      );

  final String range;
  final DateTime? since;
  final DateTime? until;
  final List<PipelineStatusItem> leadsByStatus;
  final int convertedCustomers;
  final int lostLeads;
  final int activeLeads;
  final List<PipelineSourceItem> sourcePerformance;
  final List<PipelinePriorityItem> priorityDistribution;
}
