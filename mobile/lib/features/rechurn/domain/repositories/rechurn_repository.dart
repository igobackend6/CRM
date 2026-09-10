import '../entities/rechurn_page.dart';

/// Every method takes the caller's own accessToken explicitly — same
/// convention as LeadRepository/PipelineRepository.
abstract class RechurnRepository {
  Future<RechurnPage> getQueue({
    required String accessToken,
    required String workspaceId,
    String? segment,
    int inactiveDays = 30,
    String? assignedMemberId,
    String? priority,
    String? statusId,
    String? sourceId,
    String? search,
    int limit = 20,
    int offset = 0,
  });
}
