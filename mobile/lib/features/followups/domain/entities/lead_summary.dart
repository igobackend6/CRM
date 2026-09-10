/// Display-only lead identity — "which lead is this follow-up for".
/// Mirrors the backend's `LeadSummary` (backend/app/schemas/leads.py),
/// deliberately smaller than the full `Lead` entity (leads feature)
/// since a follow-up only ever needs the name to display, not
/// status/source/tags. Never used for authorization.
class LeadSummary {
  const LeadSummary({required this.id, required this.name});

  factory LeadSummary.fromJson(Map<String, dynamic> json) =>
      LeadSummary(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}
