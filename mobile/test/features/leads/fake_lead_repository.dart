import 'package:mobile/features/customer360/domain/entities/timeline_item.dart';
import 'package:mobile/features/customer360/domain/entities/timeline_page.dart';
import 'package:mobile/features/leads/domain/entities/allocation.dart';
import 'package:mobile/features/leads/domain/entities/bulk_action_result.dart';
import 'package:mobile/features/leads/domain/entities/interaction.dart';
import 'package:mobile/features/leads/domain/entities/lead.dart';
import 'package:mobile/features/leads/domain/entities/lead_bulk_action.dart';
import 'package:mobile/features/leads/domain/entities/lead_draft.dart';
import 'package:mobile/features/leads/domain/entities/lead_import_state.dart';
import 'package:mobile/features/leads/domain/entities/lead_page.dart';
import 'package:mobile/features/leads/domain/entities/lead_source.dart';
import 'package:mobile/features/leads/domain/entities/lead_status.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/leads/domain/entities/tag.dart';
import 'package:mobile/features/leads/domain/repositories/lead_repository.dart';

TimelineItem testTimelineItem({String id = 'interaction:i1', String type = 'note', DateTime? occurredAt, String summary = 'A note'}) =>
    TimelineItem(id: id, type: type, occurredAt: occurredAt ?? DateTime.utc(2026, 1, 1), summary: summary, details: const {});

Lead testLead({
  String id = 'lead-1',
  String name = 'Acme Corp',
  List<Tag> tags = const [],
  bool isCustomer = false,
  MemberSummary? createdBy,
}) =>
    Lead(
      id: id,
      workspaceId: 'w1',
      name: name,
      phone: '+15551234567',
      email: 'acme@example.com',
      priority: 'medium',
      isCustomer: isCustomer,
      createdByMember: createdBy,
      tags: tags,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class FakeLeadRepository implements LeadRepository {
  List<Lead> leadsToReturn = [];
  int totalToReturn = 0;
  Object? listError;
  Object? getError;
  Lead? leadToReturn;
  Object? createError;
  Object? updateError;
  Object? tagError;
  List<Interaction> interactionsToReturn = const [];
  List<LeadStatus> statusesToReturn = const [];
  List<LeadSource> sourcesToReturn = const [];
  List<Tag> tagsToReturn = const [];
  List<MemberSummary> membersToReturn = const [];
  Object? membersError;
  Duration membersDelay = Duration.zero;
  List<Allocation> allocationsToReturn = const [];
  Object? assignError;
  BulkActionResult? bulkActionResultToReturn;
  Object? bulkActionError;
  LeadImportResult? importResultToReturn;
  Object? importError;
  List<TimelineItem> activityItemsToReturn = const [];
  int activityTotalToReturn = 0;
  Object? activityError;
  int? lastActivityOffset;
  TimelineItem? noteToReturn;
  Object? createNoteError;
  String? lastNoteText;
  Object? convertError;
  bool lastConvertCalled = false;
  Duration convertDelay = Duration.zero;

  String? lastSearch;
  int? lastOffset;
  String? lastStatusId;
  String? lastSourceId;
  String? lastFilterAssignedMemberId;
  String? lastPriority;
  bool? lastIsCustomer;
  DateTime? lastCreatedFrom;
  DateTime? lastCreatedTo;
  String? lastTagId;
  LeadDraft? lastCreateDraft;
  LeadDraft? lastUpdateDraft;
  String? lastAssignedMemberId;
  bool lastAssignCalled = false;
  List<String>? lastBulkLeadIds;
  LeadBulkAction? lastBulkAction;
  String? lastBulkMemberId;
  String? lastBulkStatusId;
  String? lastImportCsvContent;

  /// What countVisibleLeads answers; defaults to [totalToReturn].
  int? visibleTotalToReturn;
  int countVisibleCallCount = 0;
  bool? lastCountIsCustomer;

  @override
  Future<int> countVisibleLeads({required String accessToken, required String workspaceId, bool? isCustomer}) async {
    countVisibleCallCount++;
    lastCountIsCustomer = isCustomer;
    return visibleTotalToReturn ?? totalToReturn;
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
    if (listError != null) throw listError!;
    lastSearch = search;
    lastOffset = offset;
    lastStatusId = statusId;
    lastSourceId = sourceId;
    lastFilterAssignedMemberId = assignedMemberId;
    lastPriority = priority;
    lastIsCustomer = isCustomer;
    lastCreatedFrom = createdFrom;
    lastCreatedTo = createdTo;
    lastTagId = tagId;
    return LeadPage(items: leadsToReturn, total: totalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<Lead> getLead({required String accessToken, required String workspaceId, required String leadId}) async {
    if (getError != null) throw getError!;
    return leadToReturn ?? testLead(id: leadId);
  }

  @override
  Future<Lead> createLead({required String accessToken, required String workspaceId, required LeadDraft draft}) async {
    if (createError != null) throw createError!;
    lastCreateDraft = draft;
    return testLead(name: draft.name);
  }

  @override
  Future<Lead> updateLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required LeadDraft draft,
  }) async {
    if (updateError != null) throw updateError!;
    lastUpdateDraft = draft;
    return testLead(id: leadId, name: draft.name);
  }

  String? lastOutcomeLeadId;
  String? lastOutcomeStatusId;
  Map<String, Object?>? lastOutcomeCustomFields;
  Object? outcomeError;

  @override
  Future<Lead> applyCallOutcome({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    String? statusId,
    Map<String, Object?>? customFields,
  }) async {
    if (outcomeError != null) throw outcomeError!;
    lastOutcomeLeadId = leadId;
    lastOutcomeStatusId = statusId;
    lastOutcomeCustomFields = customFields;
    return leadToReturn ?? testLead(id: leadId);
  }

  @override
  Future<Lead> convertLead({required String accessToken, required String workspaceId, required String leadId}) async {
    if (convertDelay > Duration.zero) await Future<void>.delayed(convertDelay);
    if (convertError != null) throw convertError!;
    lastConvertCalled = true;
    final base = leadToReturn ?? testLead(id: leadId);
    return Lead(
      id: base.id,
      workspaceId: base.workspaceId,
      name: base.name,
      phone: base.phone,
      email: base.email,
      priority: base.priority,
      status: base.status,
      source: base.source,
      assignedMember: base.assignedMember,
      createdByMember: base.createdByMember,
      isCustomer: true,
      tags: base.tags,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
    );
  }

  @override
  Future<List<LeadStatus>> listStatuses({required String accessToken, required String workspaceId}) async => statusesToReturn;

  @override
  Future<List<LeadSource>> listSources({required String accessToken, required String workspaceId}) async => sourcesToReturn;

  @override
  Future<List<Tag>> listTags({required String accessToken, required String workspaceId}) async => tagsToReturn;

  @override
  Future<Tag> createTag({required String accessToken, required String workspaceId, required String name, String? color}) async {
    return Tag(id: 'new-tag', name: name, color: color);
  }

  @override
  Future<List<Tag>> listLeadTags({required String accessToken, required String workspaceId, required String leadId}) async => [];

  @override
  Future<Tag> attachTag({required String accessToken, required String workspaceId, required String leadId, required String tagId}) async {
    if (tagError != null) throw tagError!;
    return Tag(id: tagId, name: 'Attached');
  }

  @override
  Future<void> detachTag({required String accessToken, required String workspaceId, required String leadId, required String tagId}) async {
    if (tagError != null) throw tagError!;
  }

  @override
  Future<List<Interaction>> listInteractions({required String accessToken, required String workspaceId, required String leadId}) async {
    return interactionsToReturn;
  }

  @override
  Future<List<MemberSummary>> listWorkspaceMembers({required String accessToken, required String workspaceId}) async {
    if (membersDelay > Duration.zero) await Future<void>.delayed(membersDelay);
    if (membersError != null) throw membersError!;
    return membersToReturn;
  }

  @override
  Future<Lead> assignLead({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    String? memberId,
  }) async {
    if (assignError != null) throw assignError!;
    lastAssignedMemberId = memberId;
    lastAssignCalled = true;
    final base = leadToReturn ?? testLead(id: leadId);
    MemberSummary? newAssignee;
    if (memberId != null) {
      final match = membersToReturn.where((m) => m.id == memberId);
      newAssignee = match.isNotEmpty ? match.first : MemberSummary(id: memberId, fullName: 'Assigned Rep');
    }
    return Lead(
      id: base.id,
      workspaceId: base.workspaceId,
      name: base.name,
      phone: base.phone,
      email: base.email,
      priority: base.priority,
      status: base.status,
      source: base.source,
      assignedMember: newAssignee,
      createdByMember: base.createdByMember,
      isCustomer: base.isCustomer,
      tags: base.tags,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
    );
  }

  @override
  Future<List<Allocation>> listAllocations({required String accessToken, required String workspaceId, required String leadId}) async {
    return allocationsToReturn;
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
    if (bulkActionError != null) throw bulkActionError!;
    lastBulkLeadIds = leadIds;
    lastBulkAction = action;
    lastBulkMemberId = memberId;
    lastBulkStatusId = statusId;
    return bulkActionResultToReturn ??
        BulkActionResult(
          total: leadIds.length,
          succeeded: leadIds.length,
          failed: 0,
          items: [for (final id in leadIds) BulkLeadItemResult(leadId: id, success: true)],
        );
  }

  @override
  Future<LeadImportResult> importLeads({required String accessToken, required String workspaceId, required String csvContent}) async {
    if (importError != null) throw importError!;
    lastImportCsvContent = csvContent;
    return importResultToReturn ?? const LeadImportResult(total: 0, created: 0, failed: 0, errors: []);
  }

  @override
  Future<TimelinePage> getActivity({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required int limit,
    required int offset,
  }) async {
    if (activityError != null) throw activityError!;
    lastActivityOffset = offset;
    return TimelinePage(items: activityItemsToReturn, total: activityTotalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<TimelineItem> createNote({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String text,
  }) async {
    if (createNoteError != null) throw createNoteError!;
    lastNoteText = text;
    return noteToReturn ?? testTimelineItem(summary: text);
  }
}

MemberSummary testMember(String id, String fullName) => MemberSummary(id: id, fullName: fullName);

Allocation testAllocation({
  String id = 'alloc-1',
  MemberSummary? previousMember,
  MemberSummary? assignedMember,
  MemberSummary? assignedBy,
}) =>
    Allocation(
      id: id,
      previousMember: previousMember,
      assignedMember: assignedMember ?? testMember('m2', 'Rep Two'),
      assignedBy: assignedBy ?? testMember('m0', 'Manager'),
      status: 'new',
      assignedAt: DateTime.utc(2026, 1, 1),
      createdAt: DateTime.utc(2026, 1, 1),
    );
