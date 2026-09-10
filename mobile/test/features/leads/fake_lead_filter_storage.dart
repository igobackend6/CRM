import 'package:mobile/features/leads/presentation/controllers/lead_filter_storage.dart';

/// Stands in for the real secure-storage-backed [LeadFilterStorage]
/// (Phase 14) so controller/widget tests never touch flutter_secure_
/// storage, which needs platform channels `flutter test` doesn't provide
/// — same reasoning as [FakeCsvFilePicker] (Phase 13).
class FakeLeadFilterStorage implements LeadFilterStorage {
  String? stored;

  @override
  Future<String?> readSavedViews() async => stored;

  @override
  Future<void> writeSavedViews(String json) async {
    stored = json;
  }
}
