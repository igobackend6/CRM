import 'package:flutter/material.dart';

import '../../../leads/domain/lead_list_mode.dart';
import '../../../leads/presentation/screens/lead_list_screen.dart';

/// The bottom nav's Customers tab: every lead converted to a customer (a customer IS a lead with
/// `is_customer = true`, see `RoutePaths.customerDetail`), with the full list header (status selector,
/// search, filters, pipeline board, more). It is the shared [LeadListScreen] in customers mode;
/// tapping a row opens its Customer 360 view.
class CustomersOverviewScreen extends StatelessWidget {
  const CustomersOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) => const LeadListScreen(mode: LeadListMode.customers);
}
