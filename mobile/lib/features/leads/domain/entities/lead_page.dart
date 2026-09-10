import 'lead.dart';

/// One page of `GET /leads` (backend `LeadListResponse`).
class LeadPage {
  const LeadPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<Lead> items;
  final int total;
  final int limit;
  final int offset;
}
