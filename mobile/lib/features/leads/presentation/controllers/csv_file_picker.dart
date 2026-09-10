import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// Abstraction over picking a local CSV file and reading its text
/// content (Phase 13 §Flutter "file selection"), so controller/widget
/// tests can substitute a fake without exercising the real file_picker
/// plugin, which needs platform channels `flutter test` doesn't provide.
abstract class CsvFilePicker {
  /// Returns null if the user cancelled the picker, or the picked file
  /// had no readable content.
  Future<PickedCsvFile?> pickCsvFile();
}

class PickedCsvFile {
  const PickedCsvFile({required this.fileName, required this.content});

  final String fileName;
  final String content;
}

class FilePickerCsvFilePicker implements CsvFilePicker {
  @override
  Future<PickedCsvFile?> pickCsvFile() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (files.isEmpty) return null;
    final file = files.first;
    final bytes = await file.readAsBytes();
    return PickedCsvFile(fileName: file.name, content: utf8.decode(bytes, allowMalformed: true));
  }
}
