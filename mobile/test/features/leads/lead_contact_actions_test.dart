import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/external_url_launcher.dart';
import 'package:mobile/features/dialer/presentation/providers/native_dialer_providers.dart';
import 'package:mobile/features/leads/presentation/providers/leads_providers.dart';
import 'package:mobile/features/leads/presentation/widgets/lead_contact_actions.dart';
import 'package:mobile/features/whatsapp/domain/phone_number_normalizer.dart';

import '../dialer/fake_native_dialer_service.dart';

class _RecordingLauncher implements ExternalUrlLauncher {
  final List<Uri> launched = [];
  bool result = true;

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return result;
  }
}

Future<_RecordingLauncher> _pump(WidgetTester tester, {required String? phone, bool launchWorks = true}) async {
  final launcher = _RecordingLauncher()..result = launchWorks;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [leadContactLauncherProvider.overrideWithValue(launcher), nativeDialerServiceProvider.overrideWithValue(FakeNativeDialerService())],
      child: MaterialApp(home: Scaffold(body: Center(child: LeadContactActions(phone: phone)))),
    ),
  );
  return launcher;
}

void main() {
  group('LeadContactActions', () {
    testWidgets('shows a Call and a WhatsApp call button', (tester) async {
      await _pump(tester, phone: '8925958929');

      expect(find.byKey(const Key('lead-call-button')), findsOneWidget);
      expect(find.byKey(const Key('lead-whatsapp-call-button')), findsOneWidget);
      expect(find.byTooltip('Call'), findsOneWidget);
      expect(find.byTooltip('WhatsApp call'), findsOneWidget);
    });

    testWidgets('Call opens the normal dialer with the number filled in', (tester) async {
      final launcher = await _pump(tester, phone: '8925958929');

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      expect(launcher.launched.single.toString(), 'tel:8925958929');
    });

    testWidgets('spaces and dashes are removed from the dialed number but a leading + is kept', (tester) async {
      final launcher = await _pump(tester, phone: '+91 89259-58929');

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      expect(launcher.launched.single.scheme, 'tel');
      expect(launcher.launched.single.path, '+918925958929');
    });

    testWidgets('WhatsApp opens the chat for that number, assuming +91 for a bare local number', (tester) async {
      final launcher = await _pump(tester, phone: '8925958929');

      await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
      await tester.pump();

      expect(launcher.launched.single.toString(), 'https://wa.me/918925958929');
    });

    testWidgets('WhatsApp keeps the country code of a number that already has one', (tester) async {
      final launcher = await _pump(tester, phone: '+1 (555) 123-4567');

      await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
      await tester.pump();

      expect(launcher.launched.single.toString(), 'https://wa.me/15551234567');
    });

    testWidgets('a number WhatsApp cannot use shows a message instead of opening anything', (tester) async {
      final launcher = await _pump(tester, phone: '12345');

      await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
      await tester.pump();

      expect(launcher.launched, isEmpty);
      expect(find.textContaining('cannot be opened in WhatsApp'), findsOneWidget);
    });

    testWidgets('a phone with no dialer app says so', (tester) async {
      await _pump(tester, phone: '8925958929', launchWorks: false);

      await tester.tap(find.byKey(const Key('lead-call-button')));
      await tester.pump();

      expect(find.text('Could not open the phone dialer.'), findsOneWidget);
    });

    testWidgets('WhatsApp not installed says so', (tester) async {
      await _pump(tester, phone: '8925958929', launchWorks: false);

      await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
      await tester.pump();

      expect(find.textContaining('Could not open WhatsApp'), findsOneWidget);
    });

    for (final phone in [null, '', '   ']) {
      testWidgets('with no phone number (${phone == null ? 'null' : "'$phone'"}) both buttons do nothing', (tester) async {
        final launcher = await _pump(tester, phone: phone);

        await tester.tap(find.byKey(const Key('lead-call-button')));
        await tester.tap(find.byKey(const Key('lead-whatsapp-call-button')));
        await tester.pump();

        expect(launcher.launched, isEmpty);
      });
    }
  });

  group('normalizePhoneForWhatsApp with a default country code', () {
    test('a bare 10-digit number gets the default country code', () {
      final result = normalizePhoneForWhatsApp('8925958929', defaultCountryCode: '91');

      expect(result.isValid, isTrue);
      expect(result.internationalDigits, '918925958929');
    });

    test('a leading 0 on an 11-digit local number is dropped', () {
      expect(normalizePhoneForWhatsApp('08925958929', defaultCountryCode: '91').internationalDigits, '918925958929');
    });

    test('separators in a local number are ignored', () {
      expect(normalizePhoneForWhatsApp('89259 58929', defaultCountryCode: '91').internationalDigits, '918925958929');
    });

    test('a number that already has + or 00 is left alone, not double-prefixed', () {
      expect(normalizePhoneForWhatsApp('+918925958929', defaultCountryCode: '91').internationalDigits, '918925958929');
      expect(normalizePhoneForWhatsApp('00918925958929', defaultCountryCode: '91').internationalDigits, '918925958929');
    });

    test('anything that is not a 10-digit local number is still invalid', () {
      expect(normalizePhoneForWhatsApp('12345', defaultCountryCode: '91').isValid, isFalse);
      expect(normalizePhoneForWhatsApp('892595892912', defaultCountryCode: '91').isValid, isFalse);
    });

    test('without a default country code a bare number is still never guessed', () {
      expect(normalizePhoneForWhatsApp('8925958929').isValid, isFalse);
    });
  });
}
