import '../entities/call.dart';
import '../entities/call_draft.dart';
import '../entities/call_outcome.dart';
import '../entities/call_page.dart';

abstract class CallRepository {
  Future<CallPage> listCalls({
    required String accessToken,
    required String workspaceId,
    String? leadId,
    String? direction,
    int limit = 20,
    int offset = 0,
  });

  Future<Call> getCall({required String accessToken, required String workspaceId, required String callId});

  Future<Call> createCall({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required CallDraft draft,
  });

  Future<List<Call>> listLeadCalls({required String accessToken, required String workspaceId, required String leadId});

  Future<List<CallOutcome>> listCallOutcomes({required String accessToken, required String workspaceId});
}
