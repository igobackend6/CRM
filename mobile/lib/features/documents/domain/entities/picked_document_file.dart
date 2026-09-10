/// A file the user picked for upload, already read into memory —
/// bytes/name/mimeType, nothing platform-specific left in it (see
/// data/document_file_picker.dart, the same "thin abstraction over a
/// real plugin" seam as CsvFilePicker in the leads feature).
class PickedDocumentFile {
  const PickedDocumentFile({required this.fileName, required this.bytes, required this.mimeType});

  final String fileName;
  final List<int> bytes;
  final String mimeType;
}
