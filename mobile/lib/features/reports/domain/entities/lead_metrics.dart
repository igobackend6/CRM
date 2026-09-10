/// Mirrors the backend's `LeadMetrics` (backend/app/schemas/reports.py).
/// `leadsCreated` (by me — `created_by_member_id`) is distinct from
/// `leadsAssigned` (to me — `assigned_member_id`); the two columns are
/// independent (a lead is often bulk-imported or created by one member
/// and assigned to another).
class LeadMetrics {
  const LeadMetrics({
    required this.leadsCreated,
    required this.leadsAssigned,
    required this.leadsContacted,
    required this.leadsConverted,
    required this.conversionRate,
  });

  static const empty = LeadMetrics(leadsCreated: 0, leadsAssigned: 0, leadsContacted: 0, leadsConverted: 0, conversionRate: 0.0);

  factory LeadMetrics.fromJson(Map<String, dynamic> json) => LeadMetrics(
        leadsCreated: json['leads_created'] as int? ?? 0,
        leadsAssigned: json['leads_assigned'] as int? ?? 0,
        leadsContacted: json['leads_contacted'] as int? ?? 0,
        leadsConverted: json['leads_converted'] as int? ?? 0,
        conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0.0,
      );

  final int leadsCreated;
  final int leadsAssigned;
  final int leadsContacted;
  final int leadsConverted;
  final double conversionRate;
}
