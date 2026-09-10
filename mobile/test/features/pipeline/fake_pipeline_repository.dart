import 'package:mobile/features/leads/domain/entities/lead.dart';
import 'package:mobile/features/leads/domain/entities/lead_status.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/pipeline/domain/entities/pipeline_column.dart';
import 'package:mobile/features/pipeline/domain/entities/pipeline_lead_card.dart';
import 'package:mobile/features/pipeline/domain/repositories/pipeline_repository.dart';

LeadStatus testLeadStatus({
  String id = 's1',
  String name = 'New',
  String code = 'new',
  int sortOrder = 10,
  String stage = 'in_progress',
  bool isWon = false,
  bool isLost = false,
  bool isDefault = false,
}) =>
    LeadStatus(
      id: id,
      name: name,
      code: code,
      sortOrder: sortOrder,
      stage: isWon ? 'closed_won' : (isLost ? 'closed_lost' : stage),
      isDefault: isDefault,
    );

PipelineLeadCard testPipelineLeadCard({
  String id = 'lead-1',
  String name = 'Acme Corp',
  String? phone,
  String? email,
  String priority = 'medium',
  LeadStatus? status,
  MemberSummary? assignedMember,
  DateTime? updatedAt,
}) =>
    PipelineLeadCard(
      id: id,
      name: name,
      phone: phone,
      email: email,
      priority: priority,
      status: status ?? testLeadStatus(),
      assignedMember: assignedMember,
      updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
    );

PipelineColumn testPipelineColumn({LeadStatus? status, List<PipelineLeadCard> leads = const [], int? total}) {
  final resolvedStatus = status ?? testLeadStatus();
  return PipelineColumn(status: resolvedStatus, leads: leads, total: total ?? leads.length);
}

Lead testLead({String id = 'lead-1', String name = 'Acme Corp', LeadStatus? status}) => Lead(
      id: id,
      workspaceId: 'w1',
      name: name,
      priority: 'medium',
      status: status ?? testLeadStatus(),
      isCustomer: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class FakePipelineRepository implements PipelineRepository {
  List<PipelineColumn> columnsToReturn = [];
  Object? getPipelineError;

  Lead? statusChangeResult;
  Object? changeStatusError;

  String? lastSearch;
  String? lastLeadId;
  String? lastStatusId;
  int changeStatusCallCount = 0;

  @override
  Future<List<PipelineColumn>> getPipeline({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? assignedMemberId,
    String? sourceId,
    int limit = 20,
    int offset = 0,
  }) async {
    if (getPipelineError != null) throw getPipelineError!;
    lastSearch = search;
    return columnsToReturn;
  }

  @override
  Future<Lead> changeLeadStatus({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String statusId,
  }) async {
    changeStatusCallCount++;
    if (changeStatusError != null) throw changeStatusError!;
    lastLeadId = leadId;
    lastStatusId = statusId;
    return statusChangeResult ?? testLead(id: leadId);
  }
}
