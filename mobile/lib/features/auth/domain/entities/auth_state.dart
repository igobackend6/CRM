import 'app_user.dart';

/// Phase 4 §5 states, plus `mustChangePassword` for the admin-issued-
/// password model: a signed-in session whose `user_metadata` still
/// carries `must_change_password = true` and must be blocked from the
/// rest of the app until it sets its own password.
enum AuthStatus { initializing, unauthenticated, authenticating, mustChangePassword, authenticated, error }

class AuthState {
  const AuthState._({required this.status, this.user, this.errorMessage});

  const AuthState.initializing() : this._(status: AuthStatus.initializing);
  const AuthState.unauthenticated() : this._(status: AuthStatus.unauthenticated);
  const AuthState.authenticating() : this._(status: AuthStatus.authenticating);
  const AuthState.mustChangePassword() : this._(status: AuthStatus.mustChangePassword);
  const AuthState.authenticated(AppUser user) : this._(status: AuthStatus.authenticated, user: user);
  const AuthState.error(String message) : this._(status: AuthStatus.error, errorMessage: message);

  final AuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;
}
