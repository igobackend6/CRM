import '../../../leads/domain/entities/lead.dart';
import '../entities/pipeline_column.dart';

/// Every method takes the caller's own accessToken explicitly — same
/// convention as LeadRepository/DashboardRepository (Phase 5/11) rather
/// than the repository holding a token internally.
abstract class PipelineRepository {
  Future<List<PipelineColumn>> getPipeline({
    required String accessToken,
    required String workspaceId,
    String? search,
    String? assignedMemberId,
    String? sourceId,
    int limit = 20,
    int offset = 0,
  });

  /// Returns the updated lead (full `LeadOut` shape, same as
  /// `LeadRepository.updateLead`) so the caller can, if it wants,
  /// re-derive display state without a second fetch.
  Future<Lead> changeLeadStatus({
    required String accessToken,
    required String workspaceId,
    required String leadId,
    required String statusId,
  });
}
