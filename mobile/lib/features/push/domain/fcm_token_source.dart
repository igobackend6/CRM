/// The one seam between this app and Firebase. Everything push-related
/// downstream is written against this interface, so wiring a real
/// Firebase project later means adding one implementation and swapping a
/// provider — nothing else changes.
///
/// Until a Firebase project exists (see docs/setup/push-notifications.md),
/// [NoopFcmTokenSource] is the wired implementation: [getToken] returns
/// null, so registration silently does nothing and the in-app
/// notification (notifications table + Realtime badge) is the only
/// channel.
abstract class FcmTokenSource {
  /// The current FCM registration token, or null when push isn't
  /// available (no Firebase, permission denied, simulator, ...).
  Future<String?> getToken();

  /// Fires whenever FCM rotates the token — the app must re-register the
  /// new one. Empty stream when push isn't available.
  Stream<String> get onTokenRefresh;

  /// Drop the local token (called on logout, after the backend has been
  /// told to forget it).
  Future<void> deleteToken();
}
