import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/external_url_launcher.dart';
import 'package:mobile/features/dialer/domain/native_dialer_models.dart';
import 'package:mobile/features/dialer/presentation/providers/dialer_providers.dart';
import 'package:mobile/features/dialer/presentation/providers/native_dialer_providers.dart';
import 'package:mobile/features/dialer/presentation/screens/default_dialer_screen.dart';
import 'package:mobile/features/dialer/presentation/screens/dialer_screen.dart';
import 'package:mobile/features/sim/data/sim_repository.dart';
import 'package:mobile/features/sim/domain/sim_card.dart';
import 'package:mobile/features/sim/presentation/providers/sim_providers.dart';

import '../sim/sim_fakes.dart';
import 'fake_native_dialer_service.dart';

class _Launcher implements ExternalUrlLauncher {
  final List<Uri> launched = [];
  bool works = true;

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return works;
  }
}

ProviderContainer _container(FakeNativeDialerService service, {_Launcher? launcher, FakeSimSelectionStorage? simStorage}) {
  final c = ProviderContainer(
    overrides: [
      nativeDialerServiceProvider.overrideWithValue(service),
      dialerUrlLauncherProvider.overrideWithValue(launcher ?? _Launcher()),
      simPlatformSourceProvider.overrideWithValue(FakeSimPlatformSource()),
      simSelectionStorageProvider.overrideWithValue(simStorage ?? FakeSimSelectionStorage()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('DefaultDialerController', () {
    test('reflects what the phone says, and turning on asks Android', () async {
      final service = FakeNativeDialerService();
      final c = _container(service);
      final controller = c.read(defaultDialerControllerProvider.notifier);
      await controller.refresh();
      expect(c.read(defaultDialerControllerProvider).isDefault, isFalse);

      await controller.turnOn();

      expect(service.roleRequests, 1);
      expect(c.read(defaultDialerControllerProvider).isDefault, isTrue);
      expect(c.read(defaultDialerControllerProvider).message, isNull);
    });

    test('if the member says no, it stays off and says calls keep using Google Phone', () async {
      final service = FakeNativeDialerService(grantsRole: false);
      final c = _container(service);
      await c.read(defaultDialerControllerProvider.notifier).turnOn();

      final state = c.read(defaultDialerControllerProvider);
      expect(state.isDefault, isFalse);
      expect(state.message, contains('Google Phone'));
    });

    test('turning off opens Android\'s Default apps (apps cannot give the role back)', () async {
      final service = FakeNativeDialerService(isDefault: true);
      final c = _container(service);
      await c.read(defaultDialerControllerProvider.notifier).openDefaultAppsSettings();
      expect(service.settingsOpens, 1);
    });
  });

  group('CallPlacer', () {
    test('not the Phone app: opens the phone\'s own dialer, exactly as before', () async {
      final service = FakeNativeDialerService();
      final launcher = _Launcher();
      final c = _container(service);

      final result = await c.read(callPlacerProvider).place('+91 98765-43210', fallback: launcher);

      expect(result, CallStartResult.openedSystemDialer);
      expect(launcher.launched.single.toString(), 'tel:+919876543210');
      expect(service.placed, isEmpty);
    });

    test('not the Phone app and the dialer cannot open: failed', () async {
      final launcher = _Launcher()..works = false;
      final c = _container(FakeNativeDialerService());
      expect(await c.read(callPlacerProvider).place('9876543210', fallback: launcher), CallStartResult.failed);
    });

    test('the Phone app: places the call itself, without opening the other dialer', () async {
      final service = FakeNativeDialerService(isDefault: true);
      final launcher = _Launcher();
      final c = _container(service);

      final result = await c.read(callPlacerProvider).place('9876543210', fallback: launcher);

      expect(result, CallStartResult.placedByCrm);
      expect(service.placed.single.number, '9876543210');
      expect(launcher.launched, isEmpty);
    });

    test('asks for the Phone permission once, and stops if it is refused', () async {
      final service = FakeNativeDialerService(isDefault: true, callPermission: false, grantsCallPermission: false);
      final c = _container(service);

      expect(await c.read(callPlacerProvider).place('9876543210', fallback: _Launcher()), CallStartResult.permissionDenied);
      expect(service.permissionRequests, 1);
      expect(service.placed, isEmpty);
    });

    test('uses the business SIM, unless another was picked on the dialer', () async {
      final simStorage = FakeSimSelectionStorage();
      await SimRepository(FakeSimPlatformSource(), simStorage).select('user-1', const SimCard(subscriptionId: 7, slotIndex: 1, carrierName: 'airtel'));
      final service = FakeNativeDialerService(isDefault: true);
      final c = _container(service, simStorage: simStorage);
      // The business SIM is stored per signed-in employee; without one signed in the placer uses Android's default.
      await c.read(callPlacerProvider).place('9876543210', fallback: _Launcher());
      expect(service.placed.last.subscriptionId, isNull);

      c.read(dialerSimChoiceProvider.notifier).state = 3;
      await c.read(callPlacerProvider).place('9876543210', fallback: _Launcher());
      expect(service.placed.last.subscriptionId, 3);
    });

    test('empty and junk numbers are refused before anything happens', () async {
      final service = FakeNativeDialerService(isDefault: true);
      final c = _container(service);
      expect(await c.read(callPlacerProvider).place('', fallback: _Launcher()), CallStartResult.invalidNumber);
      expect(await c.read(callPlacerProvider).place('abc', fallback: _Launcher()), CallStartResult.invalidNumber);
      expect(service.placed, isEmpty);
    });

    test('Android\'s refusal reasons are passed on', () async {
      final service = FakeNativeDialerService(isDefault: true)..placeResult = PlaceCallResult.permissionDenied;
      final c = _container(service);
      expect(await c.read(callPlacerProvider).place('9876543210', fallback: _Launcher()), CallStartResult.permissionDenied);
      service.placeResult = PlaceCallResult.unavailable;
      expect(await c.read(callPlacerProvider).place('9876543210', fallback: _Launcher()), CallStartResult.failed);
    });
  });

  group('Default Dialer screen', () {
    Future<ProviderContainer> pump(WidgetTester tester, FakeNativeDialerService service) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _container(service);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: DefaultDialerScreen())));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('off: says Not default and explains Google Phone recording stops while on', (tester) async {
      await pump(tester, FakeNativeDialerService());
      expect(find.text('Not default'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('default-dialer-switch'))).value, isFalse);
      expect(find.byKey(const Key('default-dialer-warning')), findsOneWidget);
      expect(find.textContaining('call recording stops working'), findsOneWidget);
      expect(find.textContaining('Emergency calls always work'), findsOneWidget);
    });

    testWidgets('turning the switch on asks Android and then shows Default Phone App', (tester) async {
      final service = FakeNativeDialerService();
      await pump(tester, service);

      await tester.tap(find.byKey(const Key('default-dialer-switch')));
      await tester.pumpAndSettle();

      expect(service.roleRequests, 1);
      expect(find.text('Default Phone App'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('default-dialer-switch'))).value, isTrue);
    });

    testWidgets('a refused request leaves it off with a friendly note', (tester) async {
      await pump(tester, FakeNativeDialerService(grantsRole: false));

      await tester.tap(find.byKey(const Key('default-dialer-switch')));
      await tester.pumpAndSettle();

      expect(find.text('Not default'), findsOneWidget);
      expect(find.byKey(const Key('default-dialer-message')), findsOneWidget);
    });

    testWidgets('turning it off explains how to hand the phone back, then opens Default apps', (tester) async {
      final service = FakeNativeDialerService(isDefault: true);
      await pump(tester, service);
      expect(find.text('Default Phone App'), findsOneWidget);

      await tester.tap(find.byKey(const Key('default-dialer-switch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('default-dialer-off-dialog')), findsOneWidget);
      expect(find.textContaining('Phone (Google)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('default-dialer-open-settings')));
      await tester.pumpAndSettle();
      expect(service.settingsOpens, 1);
    });

    testWidgets('cancelling that dialog changes nothing', (tester) async {
      final service = FakeNativeDialerService(isDefault: true);
      await pump(tester, service);
      await tester.tap(find.byKey(const Key('default-dialer-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.settingsOpens, 0);
    });

    testWidgets('a phone that does not offer the role disables the switch and says so', (tester) async {
      await pump(tester, FakeNativeDialerService(available: false));
      expect(find.byKey(const Key('default-dialer-unavailable')), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('default-dialer-switch'))).onChanged, isNull);
    });

    testWidgets('lists the phone\'s SIMs', (tester) async {
      await pump(tester, FakeNativeDialerService(accounts: const [PhoneAccountInfo(id: 'a', label: 'airtel', subscriptionId: 1, index: 0), PhoneAccountInfo(id: 'b', label: 'Jio', subscriptionId: 2, index: 1)]));
      expect(find.text('Your SIMs'), findsOneWidget);
      expect(find.text('airtel'), findsOneWidget);
      expect(find.text('Jio'), findsOneWidget);
    });
  });

  group('CRM dialer screen', () {
    Future<(ProviderContainer, FakeNativeDialerService, _Launcher)> pump(
      WidgetTester tester, {
      FakeNativeDialerService? service,
      String? initialNumber,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final svc = service ?? FakeNativeDialerService();
      final launcher = _Launcher();
      final c = _container(svc, launcher: launcher);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(home: DialerScreen(initialNumber: initialNumber))));
      await tester.pumpAndSettle();
      return (c, svc, launcher);
    }

    Future<void> type(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.text(d).first);
        await tester.pump();
      }
    }

    testWidgets('typing a number and tapping Call opens the phone\'s dialer when the CRM is not the Phone app', (tester) async {
      final (_, service, launcher) = await pump(tester);
      await type(tester, '9876543210');

      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      expect(launcher.launched.single.toString(), 'tel:9876543210');
      expect(service.placed, isEmpty);
    });

    testWidgets('as the Phone app, Call places the call through the CRM', (tester) async {
      final (_, service, launcher) = await pump(tester, service: FakeNativeDialerService(isDefault: true));
      await type(tester, '9876543210');

      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      expect(service.placed.single.number, '9876543210');
      expect(launcher.launched, isEmpty);
    });

    testWidgets('a refused Phone permission tells the member what to do', (tester) async {
      await pump(tester, service: FakeNativeDialerService(isDefault: true, callPermission: false, grantsCallPermission: false));
      await type(tester, '9876543210');

      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      expect(find.textContaining('Allow the Phone permission'), findsOneWidget);
    });

    testWidgets('a number from a tel: link is shown but never dialled until Call is tapped', (tester) async {
      final (_, service, launcher) = await pump(tester, initialNumber: '+91 98765 43210');
      expect(find.text('+919876543210'), findsOneWidget);
      expect(service.placed, isEmpty);
      expect(launcher.launched, isEmpty);
    });

    testWidgets('long-pressing backspace clears the whole number', (tester) async {
      await pump(tester, initialNumber: '12345');
      await tester.longPress(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(find.text('12345'), findsNothing);
    });

    testWidgets('SIM choice appears only as the Phone app on a two-SIM phone, and picking one is remembered', (tester) async {
      const accounts = [PhoneAccountInfo(id: 'a', label: 'airtel', subscriptionId: 1, index: 0), PhoneAccountInfo(id: 'b', label: 'Jio', subscriptionId: 2, index: 1)];
      await pump(tester, service: FakeNativeDialerService(accounts: accounts)); // not the Phone app
      expect(find.byKey(const Key('dialer-sim-choice')), findsNothing);
    });

    testWidgets('as the Phone app with two SIMs, both are offered and the picked one is used for the call', (tester) async {
      const accounts = [PhoneAccountInfo(id: 'a', label: 'airtel', subscriptionId: 1, index: 0), PhoneAccountInfo(id: 'b', label: 'Jio', subscriptionId: 2, index: 1)];
      final (_, service, _) = await pump(tester, service: FakeNativeDialerService(isDefault: true, accounts: accounts));
      expect(find.byKey(const Key('dialer-sim-choice')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dialer-sim-2')));
      await tester.pump();
      await type(tester, '9876543210');
      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      expect(service.placed.single.subscriptionId, 2);
    });
  });
}
