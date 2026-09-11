import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/widgets.dart';

/// The outer chrome for the bottom-nav tabs — built once by the
/// `StatefulShellRoute` in `app_router.dart` and kept alive across Home
/// / Allocations / Customers / Menu, so the footer (and each tab's own
/// scroll position/state) survives switching tabs instead of being torn
/// down and rebuilt the way a plain pushed screen would be. Each tab
/// still owns its own inner `Scaffold`/`AppBar` (e.g. `AppShellScreen`,
/// `MenuScreen`) — nesting a Scaffold inside another is normal Flutter;
/// only the parts truly shared across all four (the bar itself, the
/// call FAB) belong up here.
class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNavBar(
        currentTab: AppNavTab.values[navigationShell.currentIndex],
        onSelect: (tab) => _onSelect(context, tab),
      ),
      floatingActionButton: AppCallFab(onPressed: () => context.push(RoutePaths.dialer)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  void _onSelect(BuildContext context, AppNavTab tab) {
    final index = AppNavTab.values.indexOf(tab);
    // Re-tapping the already-active tab resets that branch back to its
    // root (e.g. clears a scrolled-in Lead Detail back to the Lead
    // List) instead of doing nothing — the common bottom-nav convention.
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }
}
