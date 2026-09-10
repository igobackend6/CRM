import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/external_url_launcher.dart';
import 'package:mobile/features/whatsapp/data/deep_link_whatsapp_provider.dart';

class _FakeExternalUrlLauncher implements ExternalUrlLauncher {
  bool shouldSucceed = true;
  Uri? lastUri;

  @override
  Future<bool> launch(Uri uri) async {
    lastUri = uri;
    return shouldSucceed;
  }
}

void main() {
  group('DeepLinkWhatsAppProvider', () {
    test('builds a wa.me deep link with the phone and URL-encoded message text', () async {
      final launcher = _FakeExternalUrlLauncher();
      final provider = DeepLinkWhatsAppProvider(launcher: launcher);

      await provider.send(internationalPhoneDigits: '15551234567', message: 'Hello there!');

      expect(launcher.lastUri!.host, 'wa.me');
      expect(launcher.lastUri!.path, '/15551234567');
      expect(launcher.lastUri!.queryParameters['text'], 'Hello there!');
      expect(launcher.lastUri!.scheme, 'https');
    });

    test('omits the text query parameter entirely for an empty message', () async {
      final launcher = _FakeExternalUrlLauncher();
      final provider = DeepLinkWhatsAppProvider(launcher: launcher);

      await provider.send(internationalPhoneDigits: '15551234567', message: '');

      expect(launcher.lastUri!.queryParameters.containsKey('text'), isFalse);
    });

    test('propagates the launcher\'s own success/failure result', () async {
      final launcher = _FakeExternalUrlLauncher()..shouldSucceed = false;
      final provider = DeepLinkWhatsAppProvider(launcher: launcher);

      expect(await provider.send(internationalPhoneDigits: '15551234567', message: 'hi'), isFalse);
    });
  });
}
