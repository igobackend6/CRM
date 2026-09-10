import 'follow_up.dart';

/// One page of `GET /follow-ups` (backend `FollowUpListResponse`).
class FollowUpPage {
  const FollowUpPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<FollowUp> items;
  final int total;
  final int limit;
  final int offset;
}
