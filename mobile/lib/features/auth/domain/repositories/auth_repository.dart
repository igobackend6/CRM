import '../entities/profile.dart';
import '../entities/session_info.dart';

/// Supabase Auth is the only authentication system — this interface is a
/// thin seam over it for testability, not an abstraction meant to
/// support swapping auth providers later.
abstract class AuthRepository {
  /// Null if there is no existing session to restore.
  SessionInfo? readCurrentSession();

  /// Fires on every Supabase auth change: sign-in, sign-out, token
  /// refresh, session restored from storage.
  Stream<void> get authStateChanges;

  /// Throws NotFoundError-equivalent (see AuthController) if no
  /// `profiles` row exists for this user id.
  Future<Profile> loadProfile(String userId);

  Future<void> signInWithEmailPassword({required String email, required String password});

  Future<void> signOut();
}
