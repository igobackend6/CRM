import 'package:flutter/material.dart';

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
    );
  }
}
