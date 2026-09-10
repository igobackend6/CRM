import 'package:mobile/features/leads/domain/entities/lead_status.dart';
import 'package:mobile/features/leads/domain/entities/member_summary.dart';
import 'package:mobile/features/rechurn/domain/entities/rechurn_lead_card.dart';
import 'package:mobile/features/rechurn/domain/entities/rechurn_next_follow_up.dart';
import 'package:mobile/features/rechurn/domain/entities/rechurn_page.dart';
import 'package:mobile/features/rechurn/domain/repositories/rechurn_repository.dart';

LeadStatus testRechurnStatus({String id = 's1', String name = 'New', bool isWon = false, bool isLost = false}) =>
    LeadStatus(
      id: id,
      name: name,
      code: name.toLowerCase(),
      sortOrder: 10,
      stage: isWon ? 'closed_won' : (isLost ? 'closed_lost' : 'in_progress'),
      isDefault: false,
    );

RechurnLeadCard testRechurnLeadCard({
  String id = 'lead-1',
  String name = 'Acme Corp',
  String priority = 'medium',
  LeadStatus? status,
  MemberSummary? assignedMember,
  bool isCustomer = false,
  DateTime? lastActivityAt,
  RechurnNextFollowUp? nextFollowUp,
}) =>
    RechurnLeadCard(
      id: id,
      name: name,
      phone: '+15551234567',
      email: 'acme@example.com',
      priority: priority,
      status: status ?? testRechurnStatus(),
      assignedMember: assignedMember,
      isCustomer: isCustomer,
      lastActivityAt: lastActivityAt ?? DateTime.utc(2026, 1, 1),
      nextFollowUp: nextFollowUp,
    );

class FakeRechurnRepository implements RechurnRepository {
  List<RechurnLeadCard> itemsToReturn = [];
  int totalToReturn = 0;
  Object? getQueueError;

  String? lastSegment;
  int? lastInactiveDays;
  String? lastSearch;
  int? lastOffset;

  @override
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
  }) async {
    if (getQueueError != null) throw getQueueError!;
    lastSegment = segment;
    lastInactiveDays = inactiveDays;
    lastSearch = search;
    lastOffset = offset;
    return RechurnPage(items: itemsToReturn, total: totalToReturn, limit: limit, offset: offset);
  }
}
