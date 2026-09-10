import 'package:mobile/features/leads/presentation/controllers/csv_file_picker.dart';

/// Stands in for the real file_picker-backed [CsvFilePicker] (Phase 13)
/// so controller/widget tests never touch the actual plugin, which
/// needs platform channels `flutter test` doesn't provide.
class FakeCsvFilePicker implements CsvFilePicker {
  PickedCsvFile? fileToReturn;
  Object? errorToThrow;
  int callCount = 0;

  @override
  Future<PickedCsvFile?> pickCsvFile() async {
    callCount++;
    if (errorToThrow != null) throw errorToThrow!;
    return fileToReturn;
  }
}
