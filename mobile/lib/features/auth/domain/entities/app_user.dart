import 'profile.dart';

/// The authenticated identity: a Supabase Auth user plus their app
/// profile. `accessToken` is carried here (not re-read from Supabase
/// everywhere it's needed) because it's what services/api calls and
/// workspace RLS-respecting queries are scoped to.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.accessToken,
    required this.profile,
  });

  final String id;
  final String? email;
  final String accessToken;
  final Profile profile;
}
