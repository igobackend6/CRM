import 'app_user.dart';

/// Phase 4 §5 — the minimum required states, no more.
enum AuthStatus { initializing, unauthenticated, authenticating, authenticated, error }

class AuthState {
  const AuthState._({required this.status, this.user, this.errorMessage});

  const AuthState.initializing() : this._(status: AuthStatus.initializing);
  const AuthState.unauthenticated() : this._(status: AuthStatus.unauthenticated);
  const AuthState.authenticating() : this._(status: AuthStatus.authenticating);
  const AuthState.authenticated(AppUser user) : this._(status: AuthStatus.authenticated, user: user);
  const AuthState.error(String message) : this._(status: AuthStatus.error, errorMessage: message);

  final AuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;
}
