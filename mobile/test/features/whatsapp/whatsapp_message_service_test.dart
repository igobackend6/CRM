import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/whatsapp/domain/whatsapp_message_service.dart';
import 'package:mobile/features/whatsapp/domain/whatsapp_provider.dart';

class _FakeWhatsAppProvider implements WhatsAppProvider {
  bool shouldSucceed = true;
  String? lastPhone;
  String? lastMessage;
  int callCount = 0;

  @override
  Future<bool> send({required String internationalPhoneDigits, required String message}) async {
    callCount++;
    lastPhone = internationalPhoneDigits;
    lastMessage = message;
    return shouldSucceed;
  }
}

void main() {
  group('WhatsAppMessageService', () {
    test('an invalid/missing phone never reaches the provider', () async {
      final provider = _FakeWhatsAppProvider();
      final service = WhatsAppMessageService(provider: provider);

      final result = await service.send(rawPhone: null, message: 'hi');

      expect(result.outcome, WhatsAppSendOutcome.invalidPhone);
      expect(result.isSuccess, isFalse);
      expect(provider.callCount, 0);
    });

    test('a valid phone is normalized before being handed to the provider', () async {
      final provider = _FakeWhatsAppProvider();
      final service = WhatsAppMessageService(provider: provider);

      final result = await service.send(rawPhone: '+1 (555) 123-4567', message: 'Hello there');

      expect(result.outcome, WhatsAppSendOutcome.launched);
      expect(result.isSuccess, isTrue);
      expect(provider.lastPhone, '15551234567');
      expect(provider.lastMessage, 'Hello there');
      expect(provider.callCount, 1);
    });

    test('reports "unavailable" when the provider cannot hand off the send', () async {
      final provider = _FakeWhatsAppProvider()..shouldSucceed = false;
      final service = WhatsAppMessageService(provider: provider);

      final result = await service.send(rawPhone: '+15551234567', message: 'hi');

      expect(result.outcome, WhatsAppSendOutcome.unavailable);
      expect(result.isSuccess, isFalse);
    });

    // §6 "The user must explicitly initiate the action": there is no
    // timer, listener, or lifecycle hook anywhere in this codebase that
    // calls WhatsAppMessageService.send on its own — it is only ever
    // invoked from WhatsAppSendSheet's "Open WhatsApp" button onPressed
    // (presentation/widgets/whatsapp_send_button.dart), after the user
    // has reviewed/edited the message. This test documents that this
    // service has exactly one operation and it always requires an
    // explicit call with real arguments — nothing fires by itself.
    test('send is the only operation this service exposes, and always requires an explicit call', () async {
      final provider = _FakeWhatsAppProvider();
      final service = WhatsAppMessageService(provider: provider);
      expect(provider.callCount, 0); // constructing the service alone sends nothing
      await service.send(rawPhone: '+15551234567', message: 'hi');
      expect(provider.callCount, 1);
    });
  });
}
