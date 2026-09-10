import 'call.dart';

/// One page of `GET /calls` (backend `CallListResponse`).
class CallPage {
  const CallPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<Call> items;
  final int total;
  final int limit;
  final int offset;
}
