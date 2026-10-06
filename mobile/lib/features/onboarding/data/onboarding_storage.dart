import '../../../services/storage/secure_storage_service.dart';

/// Remembers, per install, that the intro slides were shown. Behind an
/// abstraction for the same reason [LeadFilterStorage] is — the real
/// implementation wraps flutter_secure_storage, which needs platform
/// channels `flutter test` doesn't provide.
abstract class OnboardingStorage {
  Future<bool> isSeen();

  Future<void> markSeen();
}

class SecureOnboardingStorage implements OnboardingStorage {
  SecureOnboardingStorage([SecureStorageService? storage]) : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;

  static const _key = 'onboarding_seen';

  @override
  Future<bool> isSeen() async => await _storage.read(_key) == 'true';

  @override
  Future<void> markSeen() => _storage.write(_key, 'true');
}
