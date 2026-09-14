import 'profile.dart';

/// The authenticated identity: a Supabase Auth user plus their app
/// profile. `accessToken` is carried here (not re-read from Supabase
/// everywhere it's needed) because it's what services/api calls and
/// workspace RLS-respecting queries are scoped to.
///
/// `phone` (E.164, e.g. `+91XXXXXXXXXX`) is the user's identity — the
/// admin-issued-password auth model has no email at all.
class AppUser {
  const AppUser({
    required this.id,
    required this.phone,
    required this.accessToken,
    required this.profile,
  });

  final String id;
  final String? phone;
  final String accessToken;
  final Profile profile;
}
