import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/route_paths.dart';
import '../../../analytics/presentation/widgets/analytics_floating_tab.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../../../core/widgets/brand_app_bar.dart';

/// Authenticated home shell — app bar (title, notification bell,
/// sign-out) unchanged since Phase 10; the body is the Phase 11
/// Dashboard (§"Integrate Dashboard as the authenticated app's main/home
/// screen using the existing shell. Do NOT redesign the shell."). This
/// class owns only the Scaffold/AppBar chrome — all dashboard content
/// lives in `features/dashboard/`, kept as a separate, independently
/// testable widget rather than inlined here.
///
/// This is the Home *tab's* screen, not the outer app chrome — the
/// persistent bottom nav + call FAB live one level up, in
/// `AppShellScaffold`, which wraps this and the other three tabs (see
/// `app_router.dart`'s `StatefulShellRoute`) so the bar survives
/// switching tabs instead of being rebuilt per screen.
class AppShellScreen extends ConsumerWidget {
  const AppShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: brandAppBar(
        title: Text(AppConstants.appName),
        actions: [
          // Phase 21C — same "lightweight entry point into the existing
          // shell/app bar" pattern Phase 19's rechurn button just below
          // established: one icon button, no shell redesign.
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Reports',
            onPressed: () => context.push(RoutePaths.reports),
          ),
          // Phase 19 — same "lightweight entry point into the existing
          // shell/app bar" pattern Phase 10 established just below for
          // notifications: one icon button, no shell redesign.
          IconButton(
            icon: const Icon(Icons.history_toggle_off),
            tooltip: 'Rechurn queue',
            onPressed: () => context.push(RoutePaths.rechurn),
          ),
          // Phase 10 §3's "lightweight notification entry point into the
          // existing shell/app bar" — one icon button, no shell redesign.
          IconButton(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'Notifications',
            onPressed: () => context.push(RoutePaths.notifications),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      // The Analytics hub's entry: a tab on the right edge floating over
      // the dashboard. Vertical position is a fraction of the body so it
      // clears the "Overview" heading on any screen height.
      body: Stack(
        children: [
          const DashboardScreen(),
          Align(
            alignment: const Alignment(1, -0.45),
            child: AnalyticsFloatingTab(
              key: const Key('analytics-floating-tab'),
              onTap: () => context.push(RoutePaths.analytics),
            ),
          ),
        ],
      ),
    );
  }
}
