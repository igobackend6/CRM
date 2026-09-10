import 'rechurn_lead_card.dart';

/// One page of `GET /rechurn` (backend `RechurnQueueResponse`) — mirrors
/// `LeadPage`'s shape exactly.
class RechurnPage {
  const RechurnPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<RechurnLeadCard> items;
  final int total;
  final int limit;
  final int offset;
}
