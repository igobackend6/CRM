import '../../../services/storage/secure_storage_service.dart';

/// Saves the device preferences as one string. Behind an abstraction for the same reason the other
/// local stores are — flutter_secure_storage needs platform channels `flutter test` doesn't have.
abstract class AppSettingsStorage {
  Future<String?> read();

  Future<void> write(String json);
}

class SecureAppSettingsStorage implements AppSettingsStorage {
  SecureAppSettingsStorage([SecureStorageService? storage]) : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;

  static const _key = 'app_settings';

  @override
  Future<String?> read() => _storage.read(_key);

  @override
  Future<void> write(String json) => _storage.write(_key, json);
}
