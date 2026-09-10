/// Base type for all handled exceptions in the app.
///
/// Feature-specific exceptions are added in later phases; this file only
/// establishes the shared shape so error handling stays consistent.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Network reachability or transport-level failure (timeouts, no
/// connection, DNS failure, non-2xx responses before they're mapped to a
/// more specific type in a later phase).
final class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause});
}

/// Required configuration (env values, flavor setup) is missing or invalid.
final class ConfigurationException extends AppException {
  const ConfigurationException(super.message, {super.cause});
}

/// Anything that doesn't yet have a dedicated exception type.
final class UnknownException extends AppException {
  const UnknownException(super.message, {super.cause});
}

/// Supabase Auth rejected a sign-in attempt or a session turned out to be
/// invalid (bad credentials, expired/revoked session, backend says 401).
final class AuthException extends AppException {
  const AuthException(super.message, {super.cause});
}

/// Backend returned 403 — authenticated, but not permitted (RBAC/RLS
/// denial). Added in Phase 5 for the leads API; shared by every future
/// feature's API calls rather than each inventing its own type.
final class PermissionDeniedException extends AppException {
  const PermissionDeniedException(super.message, {super.cause});
}

/// Backend returned 404 — resource doesn't exist, or isn't visible to
/// the caller (same message either way, matching the backend's
/// NotFoundError philosophy).
final class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.cause});
}

/// Backend returned 409 — the request conflicts with current state.
final class ConflictException extends AppException {
  const ConflictException(super.message, {super.cause});
}

/// Backend returned 422 — request failed validation.
final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}
