import '../entities/profile.dart';
import '../entities/session_info.dart';

/// Supabase Auth is the only authentication system — this interface is a
/// thin seam over it for testability, not an abstraction meant to
/// support swapping auth providers later.
abstract class AuthRepository {
  /// Null if there is no existing session to restore.
  SessionInfo? readCurrentSession();

  /// Fires on every Supabase auth change: sign-in, sign-out, token
  /// refresh, session restored from storage, `updateUser` completing.
  Stream<void> get authStateChanges;

  /// Throws NotFoundError-equivalent (see AuthController) if no
  /// `profiles` row exists for this user id.
  Future<Profile> loadProfile(String userId);

  /// `phone` must already be normalized to E.164 (e.g. `+91XXXXXXXXXX`)
  /// — accounts are never created or matched by email.
  Future<void> signInWithPhonePassword({required String phone, required String password});

  /// The forced first-login / post-reset password change. Also clears
  /// `must_change_password` in `user_metadata` in the same call so the
  /// gate doesn't re-trigger on the next session restore.
  Future<void> updatePassword({required String newPassword});

  Future<void> signOut();
}
