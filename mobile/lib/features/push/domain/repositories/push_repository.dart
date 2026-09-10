abstract class PushRepository {
  Future<void> registerToken({required String accessToken, required String token, required String platform});
  Future<void> deregisterToken({required String accessToken, required String token});
}
