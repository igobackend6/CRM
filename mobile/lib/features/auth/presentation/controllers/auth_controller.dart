import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../services/api/me_api_data_source.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_state.dart';
import '../../domain/entities/session_info.dart';
import '../../domain/repositories/auth_repository.dart';

/// Owns Phase 4 §5 steps 1–3 (session check, auth-change listening,
/// profile load) plus the §12 backend session check. Workspace
/// membership (§5 step 4/5) is deliberately a separate controller
/// (features/workspace) that reacts to this one becoming `authenticated`
/// — see features/workspace/presentation/controllers/workspace_controller.dart
/// and core/router/app_router.dart, which combines both to decide
/// navigation. Keeping them separate matches the two requested feature
/// folders and lets each be unit-tested independently.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, this._meApiDataSource) : super(const AuthState.initializing()) {
    _authSubscription = _repository.authStateChanges.listen((_) => _restoreFromSession());
    unawaited(_restoreFromSession());
  }

  final AuthRepository _repository;
  final MeApiDataSource _meApiDataSource;
  StreamSubscription<void>? _authSubscription;

  Future<void> _restoreFromSession() async {
    final session = _repository.readCurrentSession();
    if (session == null) {
      state = const AuthState.unauthenticated();
      return;
    }
    await _establishSession(session);
  }

  Future<void> _establishSession(SessionInfo session) async {
    try {
      final profile = await _repository.loadProfile(session.userId);
      final user = AppUser(
        id: session.userId,
        email: session.email,
        accessToken: session.accessToken,
        profile: profile,
      );

      switch (await _meApiDataSource.fetchMe(session.accessToken)) {
        case BackendMeUnauthorized():
          AppLogger.warning('Backend rejected the session (401); signing out.');
          await _repository.signOut();
          state = const AuthState.error('Your session is no longer valid. Please sign in again.');
          return;
        case BackendMeForbidden():
          state = const AuthState.error('Your account does not have access to this application.');
          return;
        case BackendMeNetworkError(:final message):
          // Non-fatal: Supabase's own session remains the source of
          // truth. The backend may simply be unreachable.
          AppLogger.warning('Could not reach backend for session check: $message');
        case BackendMeSuccess():
          break;
      }

      state = AuthState.authenticated(user);
    } on AppException catch (e) {
      state = AuthState.error(e.message);
    } catch (e) {
      AppLogger.error('Unexpected error establishing session', error: e);
      state = const AuthState.error('Something went wrong loading your account.');
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AuthState.authenticating();
    try {
      await _repository.signInWithEmailPassword(email: email, password: password);
      final session = _repository.readCurrentSession();
      if (session == null) {
        state = const AuthState.unauthenticated();
        return;
      }
      await _establishSession(session);
    } on AppException catch (e) {
      state = AuthState.error(e.message);
    } catch (e) {
      AppLogger.error('Unexpected sign-in error', error: e);
      state = const AuthState.error('Sign-in failed. Please try again.');
    }
  }

  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } catch (e) {
      AppLogger.warning('Sign-out did not complete cleanly: $e');
    }
    state = const AuthState.unauthenticated();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
