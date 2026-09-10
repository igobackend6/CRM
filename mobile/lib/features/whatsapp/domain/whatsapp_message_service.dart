import '../data/deep_link_whatsapp_provider.dart';
import 'phone_number_normalizer.dart';
import 'whatsapp_provider.dart';

enum WhatsAppSendOutcome { launched, invalidPhone, unavailable }

class WhatsAppSendResult {
  const WhatsAppSendResult(this.outcome);

  final WhatsAppSendOutcome outcome;

  bool get isSuccess => outcome == WhatsAppSendOutcome.launched;
}

/// §6/§8 — the one entry point Flutter UI calls to send a WhatsApp
/// message. Always explicitly user-initiated (§6 "The user must
/// explicitly initiate the action"): this is only ever invoked from a
/// button's `onPressed` after the user has reviewed/edited the message
/// in a preview step (see presentation/widgets/whatsapp_send_sheet.dart)
/// — there is no code path anywhere that calls this automatically.
class WhatsAppMessageService {
  WhatsAppMessageService({WhatsAppProvider? provider}) : _provider = provider ?? DeepLinkWhatsAppProvider();

  final WhatsAppProvider _provider;

  Future<WhatsAppSendResult> send({required String? rawPhone, required String message}) async {
    final normalized = normalizePhoneForWhatsApp(rawPhone);
    if (!normalized.isValid) {
      return const WhatsAppSendResult(WhatsAppSendOutcome.invalidPhone);
    }
    final launched = await _provider.send(internationalPhoneDigits: normalized.internationalDigits!, message: message);
    return WhatsAppSendResult(launched ? WhatsAppSendOutcome.launched : WhatsAppSendOutcome.unavailable);
  }
}
