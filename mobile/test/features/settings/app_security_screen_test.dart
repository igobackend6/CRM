import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/settings/presentation/providers/settings_providers.dart';
import 'package:mobile/features/settings/presentation/screens/app_security_screen.dart';

import 'settings_fakes.dart';

Future<ProviderContainer> _pump(WidgetTester tester, FakeDeviceAuthenticator authenticator) async {
  final container = settingsContainer(authenticator: authenticator);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: AppSecurityScreen())));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('turning the lock on asks the phone to confirm, then shows On', (tester) async {
    final authenticator = FakeDeviceAuthenticator();
    final container = await _pump(tester, authenticator);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('app-lock-switch'))).value, isFalse);

    await tester.tap(find.byKey(const Key('app-lock-switch')));
    await tester.pumpAndSettle();

    expect(authenticator.reasons, hasLength(1));
    expect(container.read(appSettingsControllerProvider).appLockEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('app-lock-switch'))).value, isTrue);
  });

  testWidgets('a phone without a screen lock explains what to do and stays off', (tester) async {
    final container = await _pump(tester, FakeDeviceAuthenticator(supported: false));

    await tester.tap(find.byKey(const Key('app-lock-switch')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Set a screen lock'), findsOneWidget);
    expect(container.read(appSettingsControllerProvider).appLockEnabled, isFalse);
  });

  testWidgets('cancelling the confirmation leaves the lock off and says so', (tester) async {
    final container = await _pump(tester, FakeDeviceAuthenticator(succeeds: false));

    await tester.tap(find.byKey(const Key('app-lock-switch')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not confirmed'), findsOneWidget);
    expect(container.read(appSettingsControllerProvider).appLockEnabled, isFalse);
  });
}
