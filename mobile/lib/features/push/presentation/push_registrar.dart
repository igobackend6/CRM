import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/domain/entities/auth_state.dart';
import '../domain/fcm_token_source.dart';
import '../domain/repositories/push_repository.dart';

/// Keeps the backend's `device_tokens` in sync with this device's FCM
/// token across the session lifecycle: register on login and on every
/// token refresh, deregister on logout. Booted once at app start from
/// the router's auth listener (same place `realtimeServiceProvider`
/// boots).
///
/// With [NoopFcmTokenSource] wired (the default until Firebase is set
/// up), every path here is a quiet no-op — `getToken()` returns null so
/// nothing is ever sent.
///
/// Takes an auth *stream* + the current [AuthState] rather than a `Ref`
/// so it's plain to test and doesn't depend on Riverpod internals.
class PushRegistrar {
  // A named parameter can't start with `_`, so a private field can't be
  // filled by an initializing formal here — the explicit assignment is
  // the only option.
  // ignore_for_file: prefer_initializing_formals
  PushRegistrar({
    required AuthState initialAuth,
    required Stream<AuthState> authChanges,
    required FcmTokenSource source,
    required PushRepository repository,
  })  : _source = source,
        _repository = repository {
    _wasAuthed = initialAuth.isAuthenticated;
    _currentToken = initialAuth.user?.accessToken;
    if (_wasAuthed) unawaited(_register(initialAuth.user!.accessToken));
    _authSub = authChanges.listen(_onAuth);
    _refreshSub = _source.onTokenRefresh.listen(_onTokenRefreshed);
  }

  final FcmTokenSource _source;
  final PushRepository _repository;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _refreshSub;
  String? _registeredToken;
  String? _currentToken; // current session access token, for deregister
  bool _wasAuthed = false;
  bool _busy = false;

  static String get _platform => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'web',
      };

  void _onAuth(AuthState next) {
    if (next.isAuthenticated && !_wasAuthed) {
      _currentToken = next.user!.accessToken;
      unawaited(_register(next.user!.accessToken));
    } else if (!next.isAuthenticated && _wasAuthed) {
      final token = _currentToken;
      _currentToken = null;
      if (token != null) unawaited(_deregister(token));
    } else if (next.isAuthenticated) {
      _currentToken = next.user!.accessToken;
    }
    _wasAuthed = next.isAuthenticated;
  }

  Future<void> _register(String accessToken) async {
    if (_busy) return;
    _busy = true;
    try {
      final token = await _source.getToken();
      if (token == null || token == _registeredToken) return;
      await _repository.registerToken(accessToken: accessToken, token: token, platform: _platform);
      _registeredToken = token;
    } catch (e) {
      AppLogger.warning('Push token registration failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _deregister(String accessToken) async {
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;
    try {
      await _repository.deregisterToken(accessToken: accessToken, token: token);
      await _source.deleteToken();
    } catch (e) {
      AppLogger.warning('Push token deregistration failed: $e');
    }
  }

  void _onTokenRefreshed(String _) {
    final token = _currentToken;
    // _register re-reads the token from the source and skips it if it
    // already matches _registeredToken, so a spurious refresh with an
    // unchanged token is a no-op; a genuinely new one goes through.
    if (token != null) unawaited(_register(token));
  }

  void dispose() {
    _authSub?.cancel();
    _refreshSub?.cancel();
  }
}
