import 'package:mobile/features/calls/domain/entities/call.dart';
import 'package:mobile/features/calls/domain/entities/call_draft.dart';
import 'package:mobile/features/calls/domain/entities/call_outcome.dart';
import 'package:mobile/features/calls/domain/entities/call_page.dart';
import 'package:mobile/features/calls/domain/repositories/call_repository.dart';
import 'package:mobile/features/followups/domain/entities/lead_summary.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';

Call testCall({
  String id = 'call-1',
  String leadId = 'l1',
  String leadName = 'Acme Corp',
  String direction = 'outbound',
  String state = 'ENDED',
  CallOutcome? outcome,
  DateTime? startedAt,
  int? durationSeconds,
  String? notes,
  MemberSummary? agentMember,
}) =>
    Call(
      id: id,
      workspaceId: 'w1',
      lead: LeadSummary(id: leadId, name: leadName),
      agentMember: agentMember ?? const MemberSummary(id: 'm1', fullName: 'Agent One'),
      direction: direction,
      state: state,
      outcome: outcome,
      startedAt: startedAt ?? DateTime.utc(2026, 1, 1, 9, 0),
      durationSeconds: durationSeconds,
      notes: notes,
      createdAt: DateTime.utc(2026, 1, 1, 9, 0),
    );

CallOutcome testOutcome({String id = 'oc-1', String name = 'Connected', String code = 'connected', bool isPositive = true}) =>
    CallOutcome(id: id, name: name, code: code, isPositive: isPositive, isDefault: false);

class FakeCallRepository implements CallRepository {
  List<Call> itemsToReturn = [];
  int totalToReturn = 0;
  Object? listError;
  Object? getError;
  Call? callToReturn;
  Object? createError;
  List<Call> leadCallsToReturn = const [];
  Object? leadCallsError;
  List<CallOutcome> outcomesToReturn = const [];
  Object? outcomesError;

  int? lastOffset;
  String? lastListLeadId;
  String? lastCreateLeadId;
  CallDraft? lastCreateDraft;

  @override
  Future<CallPage> listCalls({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? direction,
    int limit = 20,
    int offset = 0,
  }) async {
    if (listError != null) throw listError!;
    lastOffset = offset;
    lastListLeadId = leadId;
    return CallPage(items: itemsToReturn, total: totalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<Call> getCall({required String accessToken, required String workspaceId, required String callId}) async {
    if (getError != null) throw getError!;
    return callToReturn ?? testCall(id: callId);
  }

  @override
  Future<Call> createCall({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required CallDraft draft,
  }) async {
    if (createError != null) throw createError!;
    lastCreateLeadId = leadId;
    lastCreateDraft = draft;
    return testCall(leadId: leadId, direction: draft.direction, notes: draft.notes, durationSeconds: draft.durationSeconds);
  }

  @override
  Future<List<Call>> listLeadCalls({required String accessToken, required String workspaceId, required String leadId}) async {
    if (leadCallsError != null) throw leadCallsError!;
    return leadCallsToReturn;
  }

  @override
  Future<List<CallOutcome>> listCallOutcomes({required String accessToken, required String workspaceId}) async {
    if (outcomesError != null) throw outcomesError!;
    return outcomesToReturn;
  }
}
