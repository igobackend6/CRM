import '../domain/fcm_token_source.dart';

/// The wired [FcmTokenSource] until a Firebase project is configured.
/// Every method is a safe no-op — the app builds and runs with no
/// Firebase dependency, and push registration becomes a silent skip.
class NoopFcmTokenSource implements FcmTokenSource {
  const NoopFcmTokenSource();

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<void> deleteToken() async {}
}
