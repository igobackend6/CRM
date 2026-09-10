import '../../../leads/domain/entities/lead_status.dart';
import 'pipeline_lead_card.dart';

/// One `lead_statuses` column and the (bounded) leads currently in it.
/// `total` is the full count for this status under the current filters
/// — may be larger than `leads.length` (Phase 12 §"Support pagination
/// where practical").
class PipelineColumn {
  const PipelineColumn({required this.status, required this.leads, required this.total});

  factory PipelineColumn.fromJson(Map<String, dynamic> json) => PipelineColumn(
        status: LeadStatus.fromJson(json['status'] as Map<String, dynamic>),
        leads: (json['leads'] as List? ?? const []).cast<Map<String, dynamic>>().map(PipelineLeadCard.fromJson).toList(),
        total: json['total'] as int? ?? 0,
      );

  final LeadStatus status;
  final List<PipelineLeadCard> leads;
  final int total;

  bool get hasMore => leads.length < total;
}
