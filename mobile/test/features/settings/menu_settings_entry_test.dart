import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/router/route_paths.dart';
import 'package:mobile/features/app_shell/presentation/screens/menu_screen.dart';
import 'package:mobile/features/notifications/presentation/providers/notification_providers.dart';

import 'settings_fakes.dart';

void main() {
  testWidgets('Menu has a Settings entry (between Notifications and Sign out) that opens Settings', (tester) async {
    final container = settingsContainer(
      extraOverrides: [unreadNotificationCountProvider.overrideWith((ref) async => 0)],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: RoutePaths.menu,
      routes: [
        GoRoute(path: RoutePaths.menu, builder: (_, _) => const MenuScreen()),
        GoRoute(path: RoutePaths.settings, builder: (_, _) => const Scaffold(body: Text('SETTINGS PAGE'))),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('menu-call-history')), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('menu-settings'))).dy,
      lessThan(tester.getTopLeft(find.text('Sign out')).dy),
    );

    await tester.tap(find.byKey(const Key('menu-settings')));
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS PAGE'), findsOneWidget);
  });
}
