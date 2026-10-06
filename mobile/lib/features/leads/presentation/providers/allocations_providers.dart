import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/lead_list_state.dart';
import '../controllers/lead_request_context.dart';
import 'leads_providers.dart';

/// Every customer the signed-in member can see, before any status/date/search filter, for the
/// "shown/total" badge on the Customers header.
///
/// Recounts whenever the customer list itself finishes (re)loading, so a pull-to-refresh, a realtime
/// update or a newly converted lead moves the badge with the list.
final customersTotalProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(customerListControllerProvider.select((s) => s.status == LeadListStatus.success || s.status == LeadListStatus.empty ? s.total : -1));
  final context = resolveLeadContext(ref.read);
  if (context == null) return 0;
  return ref.read(leadRepositoryProvider).countVisibleLeads(accessToken: context.accessToken, workspaceId: context.workspaceId, isCustomer: true);
});
