import 'recent_activity_item.dart';

/// One page of `GET /dashboard/recent-activity` (backend `TimelineResponse`,
/// reused unchanged — see recent_activity_item.dart's own note).
class RecentActivityPage {
  const RecentActivityPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<RecentActivityItem> items;
  final int total;
  final int limit;
  final int offset;
}
