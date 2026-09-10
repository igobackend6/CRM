import 'document.dart';

/// One page of `GET /leads/{id}/documents` (backend `DocumentListResponse`).
class DocumentPage {
  const DocumentPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<Document> items;
  final int total;
  final int limit;
  final int offset;
}
