import 'package:mobile/features/followups/domain/entities/follow_up.dart';
import 'package:mobile/features/followups/domain/entities/follow_up_draft.dart';
import 'package:mobile/features/followups/domain/entities/follow_up_page.dart';
import 'package:mobile/features/followups/domain/entities/lead_summary.dart';
import 'package:mobile/features/followups/domain/repositories/follow_up_repository.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';

FollowUp testFollowUp({
  String id = 'fu-1',
  String leadId = 'l1',
  String leadName = 'Acme Corp',
  String type = 'call',
  DateTime? dueAt,
  String status = 'pending',
  String? notes,
  MemberSummary? assignedMember,
  bool isOverdue = false,
}) =>
    FollowUp(
      id: id,
      workspaceId: 'w1',
      lead: LeadSummary(id: leadId, name: leadName),
      type: type,
      dueAt: dueAt ?? DateTime.utc(2026, 2, 1, 9, 0),
      status: status,
      notes: notes,
      assignedMember: assignedMember,
      createdByMember: const MemberSummary(id: 'm1', fullName: 'Rep One'),
      isOverdue: isOverdue,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class FakeFollowUpRepository implements FollowUpRepository {
  List<FollowUp> itemsToReturn = [];
  int totalToReturn = 0;
  Object? listError;
  Object? getError;
  FollowUp? followUpToReturn;
  Object? createError;
  Object? updateError;
  Object? statusError;
  List<FollowUp> leadFollowUpsToReturn = const [];
  Object? leadFollowUpsError;

  int? lastOffset;
  String? lastCreateLeadId;
  FollowUpDraft? lastCreateDraft;
  String? lastUpdateFollowUpId;
  FollowUpDraft? lastUpdateDraft;
  String? lastStatusFollowUpId;
  String? lastStatus;

  @override
  Future<FollowUpPage> listFollowUps({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    if (listError != null) throw listError!;
    lastOffset = offset;
    return FollowUpPage(items: itemsToReturn, total: totalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<FollowUp> getFollowUp({required String accessToken, required String workspaceId, required String followUpId}) async {
    if (getError != null) throw getError!;
    return followUpToReturn ?? testFollowUp(id: followUpId);
  }

  @override
  Future<FollowUp> createFollowUp({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required FollowUpDraft draft,
  }) async {
    if (createError != null) throw createError!;
    lastCreateLeadId = leadId;
    lastCreateDraft = draft;
    return testFollowUp(leadId: leadId, type: draft.type, dueAt: draft.dueAt, notes: draft.notes);
  }

  @override
  Future<FollowUp> updateFollowUp({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required FollowUpDraft draft,
  }) async {
    if (updateError != null) throw updateError!;
    lastUpdateFollowUpId = followUpId;
    lastUpdateDraft = draft;
    final base = followUpToReturn ?? testFollowUp(id: followUpId);
    return testFollowUp(
      id: followUpId,
      leadId: base.lead.id,
      leadName: base.lead.name,
      type: draft.type,
      dueAt: draft.dueAt,
      status: draft.status ?? base.status,
      notes: draft.notes,
      assignedMember: base.assignedMember,
    );
  }

  @override
  Future<FollowUp> updateFollowUpStatus({
    required String accessToken,
    required String workspaceId,
    required String followUpId,
    required String status,
  }) async {
    if (statusError != null) throw statusError!;
    lastStatusFollowUpId = followUpId;
    lastStatus = status;
    final base = followUpToReturn ?? testFollowUp(id: followUpId);
    return testFollowUp(
      id: followUpId,
      leadId: base.lead.id,
      leadName: base.lead.name,
      type: base.type,
      dueAt: base.dueAt,
      status: status,
      notes: base.notes,
      assignedMember: base.assignedMember,
    );
  }

  @override
  Future<List<FollowUp>> listLeadFollowUps({required String accessToken, required String workspaceId, required String leadId}) async {
    if (leadFollowUpsError != null) throw leadFollowUpsError!;
    return leadFollowUpsToReturn;
  }
}
