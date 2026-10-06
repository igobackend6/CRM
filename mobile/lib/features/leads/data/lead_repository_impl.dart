import '../../customer360/domain/entities/timeline_item.dart';
import '../../customer360/domain/entities/timeline_page.dart';
import '../../../services/api/lead_api_data_source.dart';
import '../domain/entities/allocation.dart';
import '../domain/entities/bulk_action_result.dart';
import '../domain/entities/interaction.dart';
import '../domain/entities/lead.dart';
import '../domain/entities/lead_bulk_action.dart';
import '../domain/entities/lead_draft.dart';
import '../domain/entities/lead_import_state.dart';
import '../domain/entities/lead_page.dart';
import '../domain/entities/lead_source.dart';
import '../domain/entities/lead_status.dart';
import '../domain/entities/member_summary.dart';
import '../domain/entities/tag.dart';
import '../domain/repositories/lead_repository.dart';

class LeadRepositoryImpl implements LeadRepository {
  LeadRepositoryImpl(this._dataSource);

  final LeadApiDataSource _dataSource;

  @override
  Future<int> countVisibleLeads({required String accessToken, required String workspaceId, bool? isCustomer}) async {
    final json = await _dataSource.listLeads(accessToken: accessToken, workspaceId: workspaceId, isCustomer: isCustomer, limit: 1, offset: 0);
    return json['total'] as int? ?? 0;
  }

  @override
  Future<LeadPage> listLeads({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? statusId,
    String? sourceId,
    String? assignedMemberId,
    String? priority,
    bool? isCustomer,
    DateTime? createdFrom,
    DateTime? createdTo,
    String? tagId,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _dataSource.listLeads(
      accessToken: accessToken,
      workspaceId: workspaceId,
      search: search,
      statusId: statusId,
      sourceId: sourceId,
      assignedMemberId: assignedMemberId,
      priority: priority,
      isCustomer: isCustomer,
      createdFrom: createdFrom,
      createdTo: createdTo,
      tagId: tagId,
      limit: limit,
      offset: offset,
    );
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(Lead.fromJson).toList();
    return LeadPage(
      items: items,
      total: json['total'] as int? ?? items.length,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }

  @override
  Future<Lead> getLead({required String accessToken, required String workspaceId, required String leadId}) async {
    final json = await _dataSource.getLead(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return Lead.fromJson(json);
  }

  @override
  Future<Lead> createLead({required String accessToken, required String workspaceId, required LeadDraft draft}) async {
    final json = await _dataSource.createLead(accessToken: accessToken, workspaceId: workspaceId, body: draft.toJson());
    return Lead.fromJson(json);
  }

  @override
  Future<Lead> updateLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required LeadDraft draft,
  }) async {
    final json = await _dataSource.updateLead(
      accessToken: accessToken,
      workspaceId: workspaceId,
      leadId: leadId,
      body: draft.toJson(),
    );
    return Lead.fromJson(json);
  }

  @override
  Future<Lead> applyCallOutcome({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    String? statusId,
    Map<String, Object?>? customFields,
  }) async {
    final json = await _dataSource.updateLead(
      accessToken: accessToken,
      workspaceId: workspaceId,
      leadId: leadId,
      body: {
        'status_id': ?statusId,
        'custom_fields': ?customFields,
      },
    );
    return Lead.fromJson(json);
  }

  @override
  Future<Lead> convertLead({required String accessToken, required String workspaceId, required String leadId}) async {
    final json = await _dataSource.convertLead(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return Lead.fromJson(json);
  }

  @override
  Future<List<LeadStatus>> listStatuses({required String accessToken, required String workspaceId}) async {
    final list = await _dataSource.listStatuses(accessToken: accessToken, workspaceId: workspaceId);
    return list.cast<Map<String, dynamic>>().map(LeadStatus.fromJson).toList();
  }

  @override
  Future<List<LeadSource>> listSources({required String accessToken, required String workspaceId}) async {
    final list = await _dataSource.listSources(accessToken: accessToken, workspaceId: workspaceId);
    return list.cast<Map<String, dynamic>>().map(LeadSource.fromJson).toList();
  }

  @override
  Future<List<Tag>> listTags({required String accessToken, required String workspaceId}) async {
    final list = await _dataSource.listTags(accessToken: accessToken, workspaceId: workspaceId);
    return list.cast<Map<String, dynamic>>().map(Tag.fromJson).toList();
  }

  @override
  Future<Tag> createTag({required String accessToken, required String workspaceId, required String name, String? color}) async {
    final json = await _dataSource.createTag(
      accessToken: accessToken,
      workspaceId: workspaceId,
      body: {'name': name, 'color': ?color},
    );
    return Tag.fromJson(json);
  }

  @override
  Future<List<Tag>> listLeadTags({required String accessToken, required String workspaceId, required String leadId}) async {
    final list = await _dataSource.listLeadTags(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return list.cast<Map<String, dynamic>>().map(Tag.fromJson).toList();
  }

  @override
  Future<Tag> attachTag({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String tagId,
  }) async {
    final json = await _dataSource.attachTag(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId, tagId: tagId);
    return Tag.fromJson(json);
  }

  @override
  Future<void> detachTag({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String tagId,
  }) {
    return _dataSource.detachTag(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId, tagId: tagId);
  }

  @override
  Future<List<Interaction>> listInteractions({required String accessToken, required String workspaceId, required String leadId}) async {
    final list = await _dataSource.listInteractions(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return list.cast<Map<String, dynamic>>().map(Interaction.fromJson).toList();
  }

  @override
  Future<List<MemberSummary>> listWorkspaceMembers({required String accessToken, required String workspaceId}) async {
    final list = await _dataSource.listWorkspaceMembers(accessToken: accessToken, workspaceId: workspaceId);
    return list.cast<Map<String, dynamic>>().map(MemberSummary.fromJson).toList();
  }

  @override
  Future<Lead> assignLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    String? memberId,
  }) async {
    final json = await _dataSource.assignLead(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId, memberId: memberId);
    return Lead.fromJson(json);
  }

  @override
  Future<List<Allocation>> listAllocations({required String accessToken, required String workspaceId, required String leadId}) async {
    final list = await _dataSource.listAllocations(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId);
    return list.cast<Map<String, dynamic>>().map(Allocation.fromJson).toList();
  }

  @override
  Future<BulkActionResult> bulkAction({
    required String accessToken,
    required String workspaceId,
    required List<String> leadIds,
    required LeadBulkAction action,
    String? memberId,
    String? statusId,
  }) async {
    final json = await _dataSource.bulkAction(
      accessToken: accessToken,
      workspaceId: workspaceId,
      leadIds: leadIds,
      action: action.wireValue,
      memberId: memberId,
      statusId: statusId,
    );
    return BulkActionResult.fromJson(json);
  }

  @override
  Future<LeadImportResult> importLeads({required String accessToken, required String workspaceId, required String csvContent}) async {
    final json = await _dataSource.importLeads(accessToken: accessToken, workspaceId: workspaceId, csvContent: csvContent);
    return LeadImportResult.fromJson(json);
  }

  @override
  Future<TimelinePage> getActivity({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  }) async {
    final json = await _dataSource.getActivity(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId, limit: limit, offset: offset);
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(TimelineItem.fromJson).toList();
    return TimelinePage(
      items: items,
      total: json['total'] as int? ?? items.length,
      limit: json['limit'] as int? ?? limit,
      offset: json['offset'] as int? ?? offset,
    );
  }

  @override
  Future<TimelineItem> createNote({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String text,
  }) async {
    final json = await _dataSource.createNote(accessToken: accessToken, workspaceId: workspaceId, leadId: leadId, text: text);
    // Same InteractionOut -> TimelineItem adaptation as
    // CustomerRepositoryImpl.createNote (the backend route returns
    // InteractionOut, not TimelineItemOut, for both note-creation
    // endpoints) — kept identical so both callers get one consistent
    // shape back without a second round trip.
    final payload = (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TimelineItem.fromJson({
      'id': 'interaction:${json['id']}',
      'type': json['type'],
      'occurred_at': json['created_at'],
      'actor_member': json['actor_member'],
      'summary': (payload['text'] as String?) ?? 'Note',
      'details': payload,
    });
  }
}
