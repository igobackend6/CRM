import 'timeline_item.dart';

/// One page of `GET /customers/{id}/timeline` (backend `TimelineResponse`).
class TimelinePage {
  const TimelinePage({required this.items, required this.total, required this.limit, required this.offset});

  final List<TimelineItem> items;
  final int total;
  final int limit;
  final int offset;
}
