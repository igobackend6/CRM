/// Mirrors `lead_statuses` (000007 + 000026_lead_status_stage.sql) —
/// workspace-configurable name/code/order; `stage` is the fixed
/// four-value pipeline bucket that replaced the is_won/is_lost pair.
class LeadStatus {
  const LeadStatus({
    required this.id,
    required this.name,
    required this.code,
    required this.sortOrder,
    required this.stage,
    required this.isDefault,
  });

  factory LeadStatus.fromJson(Map<String, dynamic> json) => LeadStatus(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        sortOrder: json['sort_order'] as int? ?? 0,
        stage: json['stage'] as String? ?? 'in_progress',
        isDefault: json['is_default'] as bool? ?? false,
      );

  final String id;
  final String name;
  final String code;
  final int sortOrder;

  /// One of: `start`, `in_progress`, `closed_won`, `closed_lost`.
  final String stage;
  final bool isDefault;

  bool get isWon => stage == 'closed_won';
  bool get isLost => stage == 'closed_lost';
}
