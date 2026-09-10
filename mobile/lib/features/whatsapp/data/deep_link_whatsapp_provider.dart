import '../../../core/utils/external_url_launcher.dart';
import '../domain/whatsapp_provider.dart';

/// §6's actual scope: opens `https://wa.me/<number>?text=<message>` in
/// the installed WhatsApp app (or web.whatsapp.com as its own fallback)
/// — WhatsApp itself, not this app, performs the send once the user
/// taps its own in-app send button. No network call happens here, no
/// message content or delivery status is ever stored (§"Do NOT
/// implement... message delivery tracking").
class DeepLinkWhatsAppProvider implements WhatsAppProvider {
  DeepLinkWhatsAppProvider({ExternalUrlLauncher? launcher}) : _launcher = launcher ?? DefaultExternalUrlLauncher();

  final ExternalUrlLauncher _launcher;

  @override
  Future<bool> send({required String internationalPhoneDigits, required String message}) {
    final uri = Uri.https('wa.me', '/$internationalPhoneDigits', message.isEmpty ? null : {'text': message});
    return _launcher.launch(uri);
  }
}
