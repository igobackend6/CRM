/// Mirrors the `profiles` table (supabase/migrations/000004_profiles.sql)
/// exactly — no fields invented beyond what that table has.
class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.phone,
    this.avatarUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String id;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;
}
