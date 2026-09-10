import 'package:mobile/features/customer360/domain/entities/timeline_item.dart';
import 'package:mobile/features/customer360/domain/entities/timeline_page.dart';
import 'package:mobile/features/customer360/domain/repositories/customer_repository.dart';
import 'package:mobile/features/followups/domain/entities/follow_up.dart';
import 'package:mobile/features/leads/domain/entities/lead.dart';

Lead testCustomer({String id = 'c1', String name = 'Acme Corp', bool isCustomer = true}) => Lead(
      id: id,
      workspaceId: 'w1',
      name: name,
      phone: '+15551234567',
      email: 'acme@example.com',
      priority: 'high',
      isCustomer: isCustomer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

TimelineItem testTimelineItem({String id = 'interaction:i1', String type = 'note', DateTime? occurredAt, String summary = 'A note'}) =>
    TimelineItem(id: id, type: type, occurredAt: occurredAt ?? DateTime.utc(2026, 1, 1), summary: summary, details: const {});

class FakeCustomerRepository implements CustomerRepository {
  Lead? customerToReturn;
  Object? getCustomerError;

  List<TimelineItem> timelineItemsToReturn = const [];
  int timelineTotalToReturn = 0;
  Object? timelineError;
  int? lastTimelineOffset;

  List<FollowUp> followUpsToReturn = const [];
  Object? followUpsError;

  TimelineItem? noteToReturn;
  Object? createNoteError;
  String? lastNoteText;

  @override
  Future<Lead> getCustomer({required String accessToken, required String workspaceId, required String customerId}) async {
    if (getCustomerError != null) throw getCustomerError!;
    return customerToReturn ?? testCustomer(id: customerId);
  }

  @override
  Future<TimelinePage> getTimeline({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required int limit,
    required int offset,
  }) async {
    if (timelineError != null) throw timelineError!;
    lastTimelineOffset = offset;
    return TimelinePage(items: timelineItemsToReturn, total: timelineTotalToReturn, limit: limit, offset: offset);
  }

  @override
  Future<List<FollowUp>> listFollowUps({required String accessToken, required String workspaceId, required String customerId}) async {
    if (followUpsError != null) throw followUpsError!;
    return followUpsToReturn;
  }

  @override
  Future<TimelineItem> createNote({
    required String accessToken,
    required String workspaceId,
    required String customerId,
    required String text,
  }) async {
    if (createNoteError != null) throw createNoteError!;
    lastNoteText = text;
    return noteToReturn ?? testTimelineItem(summary: text);
  }
}
