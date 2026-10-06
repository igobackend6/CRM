import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Seam over `file_picker`'s "save as" dialog, same reason as
/// `CsvFilePicker`/`DocumentFilePicker`: `flutter test` never touches a
/// platform channel, and tests can fake the outcome. Takes raw bytes so
/// one seam serves both the CSV (Call Analytics) and PDF (Conversion
/// Funnel) exports.
abstract class FileSaver {
  /// Returns true if the user saved the file, false if they cancelled.
  Future<bool> saveBytes({required String fileName, required Uint8List bytes, required String mimeType});
}

class FilePickerFileSaver implements FileSaver {
  @override
  Future<bool> saveBytes({required String fileName, required Uint8List bytes, required String mimeType}) async {
    final saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
    return saved != null;
  }
}
