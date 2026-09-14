/// The minimal slice of a Supabase session the rest of the app needs —
/// kept separate from supabase_flutter's own Session type so the domain
/// layer doesn't depend on it directly.
class SessionInfo {
  const SessionInfo({
    required this.userId,
    required this.accessToken,
    this.phone,
    this.mustChangePassword = false,
  });

  final String userId;
  final String accessToken;
  final String? phone;

  /// Set on the auth user's `user_metadata` by the admin-users Edge
  /// Function on account creation/reset — a UX nudge (not a security
  /// boundary, since `user_metadata` is user-writable) that forces the
  /// "set your password" gate before the app is reachable.
  final bool mustChangePassword;
}
