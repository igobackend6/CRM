import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/widgets.dart';

/// Landing point for the bottom nav's Customers tab. There is no
/// customer list endpoint/screen yet (existing customers are only
/// reachable from a lead's own detail screen — see
/// `RoutePaths.customerDetail`); this is an honest placeholder rather
/// than a real list, so the tab isn't a dead tap. Building the actual
/// list is deferred workflow.
class CustomersOverviewScreen extends StatelessWidget {
  const CustomersOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: const EmptyStateView(
        icon: Icons.people_alt_outlined,
        message: 'The customer list is coming soon.\nOpen a converted lead to see its Customer 360 view.',
      ),
      // Opens the same create-lead form Allocations uses, not a separate
      // "create customer" flow — there is no direct-to-customer create
      // in this data model (a lead becomes a customer through
      // conversion, which is a business event with its own gate, not a
      // form field the client can set — see leads.is_customer's CHECK
      // constraint in 000008_leads.sql). Matches Runo's own Customers
      // screen, which keeps its "+" alongside the same center call FAB.
      floatingActionButton: FloatingActionButton(
        heroTag: 'customers-create-lead',
        tooltip: 'New lead',
        onPressed: () => context.push(RoutePaths.leadCreate),
        child: const Icon(Icons.add),
      ),
    );
  }
}
