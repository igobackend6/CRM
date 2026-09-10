import '../../../../services/storage/secure_storage_service.dart';

/// Phase 14 §"Saved Views": "prefer local secure/storage persistence".
/// Behind an abstraction for the same reason [CsvFilePicker] (Phase 13)
/// is — the real implementation wraps flutter_secure_storage, which needs
/// platform channels `flutter test` doesn't provide, so controller/widget
/// tests inject an in-memory fake instead. Deliberately just read/write a
/// single raw string (the caller owns JSON encoding), mirroring how thin
/// [SecureStorageService] itself already is.
abstract class LeadFilterStorage {
  Future<String?> readSavedViews();

  Future<void> writeSavedViews(String json);
}

class SecureLeadFilterStorage implements LeadFilterStorage {
  SecureLeadFilterStorage([SecureStorageService? storage]) : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;

  static const _key = 'lead_saved_views';

  @override
  Future<String?> readSavedViews() => _storage.read(_key);

  @override
  Future<void> writeSavedViews(String json) => _storage.write(_key, json);
}
