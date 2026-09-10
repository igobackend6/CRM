/// The minimal slice of a Supabase session the rest of the app needs —
/// kept separate from supabase_flutter's own Session type so the domain
/// layer doesn't depend on it directly.
class SessionInfo {
  const SessionInfo({required this.userId, required this.accessToken, this.email});

  final String userId;
  final String accessToken;
  final String? email;
}
