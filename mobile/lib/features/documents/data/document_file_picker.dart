import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

import '../domain/entities/picked_document_file.dart';

/// Abstraction over picking a local file for upload (§2 "Select file
/// from Flutter"), mirroring CsvFilePicker's own reasoning (leads
/// feature) — a thin seam so controller/widget tests never touch the
/// real file_picker plugin, which needs platform channels `flutter
/// test` doesn't provide.
abstract class DocumentFilePicker {
  /// Returns null if the user cancelled the picker.
  Future<PickedDocumentFile?> pickDocumentFile();
}

class FilePickerDocumentFilePicker implements DocumentFilePicker {
  @override
  Future<PickedDocumentFile?> pickDocumentFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'png', 'jpg', 'jpeg', 'txt', 'csv'],
    );
    if (files.isEmpty) return null;
    final file = files.first;
    final bytes = await file.readAsBytes();
    return PickedDocumentFile(
      fileName: file.name,
      bytes: bytes,
      mimeType: lookupMimeType(file.name) ?? 'application/octet-stream',
    );
  }
}
