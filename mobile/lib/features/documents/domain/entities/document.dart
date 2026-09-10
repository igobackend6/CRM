import '../../../leads/domain/entities/member_summary.dart';

/// Mirrors the backend's `DocumentOut` shape (backend/app/schemas/customer360.py,
/// reused as-is by the new lead-scoped documents endpoints —
/// backend/app/api/v1/documents.py). Metadata-only: no storage path/URL
/// here — a preview/download always goes through a freshly-requested,
/// short-lived signed URL (DocumentRepository.getSignedUrl), never a
/// cached one.
class Document {
  const Document({
    required this.id,
    required this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.uploadedByMember,
    required this.createdAt,
  });

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        id: json['id'] as String,
        fileName: json['file_name'] as String,
        mimeType: json['mime_type'] as String?,
        sizeBytes: json['size_bytes'] as int?,
        uploadedByMember:
            json['uploaded_by_member'] != null ? MemberSummary.fromJson(json['uploaded_by_member'] as Map<String, dynamic>) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final MemberSummary? uploadedByMember;
  final DateTime createdAt;
}
