/// Mirrors `call_outcomes` (supabase/migrations/000007_leads_pipeline_config.sql)
/// — workspace-configurable, never hardcoded client-side (Phase 9 §5).
class CallOutcome {
  const CallOutcome({
    required this.id,
    required this.name,
    required this.code,
    required this.isPositive,
    required this.isDefault,
  });

  factory CallOutcome.fromJson(Map<String, dynamic> json) => CallOutcome(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        isPositive: json['is_positive'] as bool? ?? false,
        isDefault: json['is_default'] as bool? ?? false,
      );

  final String id;
  final String name;
  final String code;
  final bool isPositive;
  final bool isDefault;
}
