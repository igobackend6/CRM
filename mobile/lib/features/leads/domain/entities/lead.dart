import 'lead_source.dart';
import 'lead_status.dart';
import 'member_summary.dart';
import 'tag.dart';

/// Mirrors the backend's `LeadOut` shape (backend/app/schemas/leads.py),
/// which is itself the enriched form of `leads`
/// (supabase/migrations/000008_leads.sql) — status/source/assigned
/// member are already resolved server-side, not raw ids, so the UI never
/// has to join reference data itself.
class Lead {
  const Lead({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.phone,
    this.email,
    required this.priority,
    this.status,
    this.source,
    this.assignedMember,
    this.createdByMember,
    required this.isCustomer,
    this.tags = const [],
    this.customFields = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
        id: json['id'] as String,
        workspaceId: json['workspace_id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        priority: json['priority'] as String? ?? 'medium',
        status: json['status'] != null ? LeadStatus.fromJson(json['status'] as Map<String, dynamic>) : null,
        source: json['source'] != null ? LeadSource.fromJson(json['source'] as Map<String, dynamic>) : null,
        assignedMember:
            json['assigned_member'] != null ? MemberSummary.fromJson(json['assigned_member'] as Map<String, dynamic>) : null,
        createdByMember:
            json['created_by_member'] != null ? MemberSummary.fromJson(json['created_by_member'] as Map<String, dynamic>) : null,
        isCustomer: json['is_customer'] as bool? ?? false,
        tags: (json['tags'] as List? ?? const []).cast<Map<String, dynamic>>().map(Tag.fromJson).toList(),
        customFields: (json['custom_fields'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String workspaceId;
  final String name;
  final String? phone;
  final String? email;
  final String priority;
  final LeadStatus? status;
  final LeadSource? source;
  final MemberSummary? assignedMember;
  final MemberSummary? createdByMember;
  final bool isCustomer;
  final List<Tag> tags;

  /// `{field_code: value}` for this lead's workspace-defined custom
  /// fields (000025_custom_fields.sql). Empty when the workspace has no
  /// custom fields or none are set.
  final Map<String, dynamic> customFields;
  final DateTime createdAt;
  final DateTime updatedAt;

  Lead copyWithTags(List<Tag> newTags) => Lead(
        id: id,
        workspaceId: workspaceId,
        name: name,
        phone: phone,
        email: email,
        priority: priority,
        status: status,
        source: source,
        assignedMember: assignedMember,
        createdByMember: createdByMember,
        isCustomer: isCustomer,
        tags: newTags,
        customFields: customFields,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
