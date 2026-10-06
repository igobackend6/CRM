import '../../../services/storage/secure_storage_service.dart';

/// Saves the business-SIM choices on this phone as one string — same shape as the other local
/// stores, and behind an abstraction because flutter_secure_storage needs platform channels.
abstract class SimSelectionStorage {
  Future<String?> read();

  Future<void> write(String json);
}

class SecureSimSelectionStorage implements SimSelectionStorage {
  SecureSimSelectionStorage([SecureStorageService? storage]) : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;

  static const _key = 'business_sim';

  @override
  Future<String?> read() => _storage.read(_key);

  @override
  Future<void> write(String json) => _storage.write(_key, json);
}
