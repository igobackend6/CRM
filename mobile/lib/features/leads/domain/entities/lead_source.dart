/// Mirrors `lead_sources` — workspace-configurable, never hardcoded (Phase 5 §5).
class LeadSource {
  const LeadSource({required this.id, required this.name, required this.code, required this.isDefault});

  factory LeadSource.fromJson(Map<String, dynamic> json) => LeadSource(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        isDefault: json['is_default'] as bool? ?? false,
      );

  final String id;
  final String name;
  final String code;
  final bool isDefault;
}
