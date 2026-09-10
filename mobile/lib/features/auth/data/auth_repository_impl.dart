import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/errors/app_exception.dart';
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
      email: session.user.email,
    );
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
