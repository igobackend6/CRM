import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/errors/app_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/entities/profile.dart';
import '../domain/entities/session_info.dart';
import '../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  SessionInfo? readCurrentSession() {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    return SessionInfo(
      userId: session.user.id,
      accessToken: session.accessToken,
      phone: session.user.phone,
      mustChangePassword: session.user.userMetadata?['must_change_password'] == true,
    );
  }

  @override
  Future<void> refreshIfExpired() async {
    final session = _client.auth.currentSession;
    if (session == null || !session.isExpired) return;
    try {
      await _client.auth.refreshSession();
    } on supa.AuthRetryableFetchException catch (e) {
      // Offline / server unreachable: keep the session, the SDK's own refresh loop retries.
      AppLogger.warning('Could not refresh the expired session (network): $e');
    } on supa.AuthException catch (e) {
      AppLogger.warning('Refresh token rejected, ending the local session: ${e.message}');
      await _client.auth.signOut(scope: supa.SignOutScope.local);
    }
  }

  @override
  Stream<void> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Future<Profile> loadProfile(String userId) async {
    try {
      final row = await _client.from('profiles').select().eq('id', userId).maybeSingle();
      if (row == null) {
        throw const AuthException('No profile found for this account. Contact your administrator.');
      }
      return Profile.fromJson(row);
    } on supa.PostgrestException catch (e) {
      throw NetworkException('Could not load your profile.', cause: e);
    } on AppException {
      rethrow;
    } catch (e) {
      throw NetworkException('Could not load your profile.', cause: e);
    }
  }

  @override
  Future<void> signInWithPhonePassword({required String phone, required String password}) async {
    try {
      await _client.auth.signInWithPassword(phone: phone, password: password);
    } on supa.AuthException catch (e) {
      throw AuthException(e.message, cause: e);
    } catch (e) {
      throw NetworkException('Could not reach the sign-in service.', cause: e);
    }
  }

  @override
  Future<void> signInWithEmailPassword({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on supa.AuthException catch (e) {
      throw AuthException(e.message, cause: e);
    } catch (e) {
      throw NetworkException('Could not reach the sign-in service.', cause: e);
    }
  }

  @override
  Future<void> updatePassword({required String newPassword}) async {
    try {
      await _client.auth.updateUser(
        supa.UserAttributes(password: newPassword, data: {'must_change_password': false}),
      );
    } on supa.AuthException catch (e) {
      throw AuthException(e.message, cause: e);
    } catch (e) {
      throw NetworkException('Could not set your new password.', cause: e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      // Sign-out should never leave the user stuck in the app — a
      // failure here is logged by the caller and treated as "signed out
      // locally" regardless (session is cleared client-side either way).
      throw UnknownException('Sign-out did not complete cleanly.', cause: e);
    }
  }
}
