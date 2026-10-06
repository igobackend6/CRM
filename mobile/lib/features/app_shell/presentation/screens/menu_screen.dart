import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../../../core/widgets/brand_app_bar.dart';

/// Landing point for the bottom nav's Menu tab — the grouped-list
/// pattern the real Runo app uses for its own Menu screen
/// (ADMINISTRATION / USER / CONFIGURATION / ...), sized down to what
/// this app actually has today: the screens/actions that used to live
/// only as icons in `AppShellScreen`'s app bar (kept there too, so
/// nothing regresses) plus the destinations the bottom nav itself
/// doesn't have a tab for.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: brandAppBar(title: const Text('Menu')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          const _MenuGroupLabel('WORKSPACE'),
          ListTile(
            key: const Key('menu-call-history'),
            leading: const Icon(Icons.call_outlined),
            title: const Text('Call History'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(RoutePaths.calls),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('Reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(RoutePaths.reports),
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('Rechurn queue'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(RoutePaths.rechurn),
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Message templates'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(RoutePaths.messageTemplates),
          ),
          const _MenuGroupLabel('ACCOUNT'),
          ListTile(
            leading: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            title: const Text('Notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(RoutePaths.notifications),
          ),
          ListTile(
            key: const Key('menu-settings'),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(RoutePaths.settings),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _MenuGroupLabel extends StatelessWidget {
  const _MenuGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textDim, letterSpacing: 0.8),
      ),
    );
  }
}
