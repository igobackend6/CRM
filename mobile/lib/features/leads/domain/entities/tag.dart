/// Mirrors `tags` (supabase/migrations/000013_reference_data.sql).
class Tag {
  const Tag({required this.id, required this.name, this.color});

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id'] as String,
        name: json['name'] as String,
        color: json['color'] as String?,
      );

  final String id;
  final String name;
  final String? color;
}
