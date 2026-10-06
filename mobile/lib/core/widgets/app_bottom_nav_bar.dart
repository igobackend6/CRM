import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// The app's four bottom-nav destinations, matching the real Runo app's
/// footer (docs/design/design-tokens.md) — Home / Allocations /
/// Customers / Menu, with a fifth "action" slot (Call) surfaced as the
/// notched center FAB rather than a fifth tab, same as the reference.
enum AppNavTab { home, allocations, customers, menu }

/// The persistent bottom navigation bar — a notched [BottomAppBar] with
/// [AppCallFab] docked in the center notch (wire both together via
/// `Scaffold.bottomNavigationBar` + `floatingActionButton:
/// floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked`,
/// see `AppShellScaffold`, the `StatefulShellRoute` wrapper in
/// `app_router.dart` that keeps this bar alive across tab switches).
/// Each tab navigates to the closest existing screen for now — see
/// `app_router.dart`'s branch routes for what each one actually shows.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({super.key, required this.currentTab, required this.onSelect});

  final AppNavTab currentTab;
  final ValueChanged<AppNavTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      // Brand blue, like the top bars; items are white (selected) / soft
      // white (the rest) on it.
      color: AppColors.accent,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavItem(
            icon: Icons.grid_view_rounded,
            label: 'Home',
            selected: currentTab == AppNavTab.home,
            onTap: () => onSelect(AppNavTab.home),
          ),
          _NavItem(
            icon: Icons.assignment_ind_outlined,
            label: 'Allocations',
            selected: currentTab == AppNavTab.allocations,
            onTap: () => onSelect(AppNavTab.allocations),
          ),
          // Reserves the space the notch cuts into, so the two left/right
          // item pairs don't crowd the docked FAB.
          const SizedBox(width: 56),
          _NavItem(
            icon: Icons.people_alt_outlined,
            label: 'Customers',
            selected: currentTab == AppNavTab.customers,
            onTap: () => onSelect(AppNavTab.customers),
          ),
          _NavItem(
            icon: Icons.menu_rounded,
            label: 'Menu',
            selected: currentTab == AppNavTab.menu,
            onTap: () => onSelect(AppNavTab.menu),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? Colors.white : Colors.white.withValues(alpha: 0.7);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom bar's docked center action — a phone dialer shortcut, the
/// same "floating call button" every Runo screen keeps on screen.
/// Opens `RoutePaths.dialer` (see `DialerScreen`).
class AppCallFab extends StatelessWidget {
  const AppCallFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.accent,
      tooltip: 'Calls',
      shape: const CircleBorder(),
      child: const Icon(Icons.call),
    );
  }
}
