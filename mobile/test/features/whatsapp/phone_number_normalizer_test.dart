import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/whatsapp/domain/phone_number_normalizer.dart';

void main() {
  group('normalizePhoneForWhatsApp', () {
    test('a missing phone number is invalid', () {
      expect(normalizePhoneForWhatsApp(null).isValid, isFalse);
      expect(normalizePhoneForWhatsApp('').isValid, isFalse);
      expect(normalizePhoneForWhatsApp('   ').isValid, isFalse);
    });

    test('a plain local number with no country-code marker is invalid', () {
      final result = normalizePhoneForWhatsApp('5551234567');
      expect(result.isValid, isFalse);
    });

    test('a number with too few digits is invalid', () {
      expect(normalizePhoneForWhatsApp('+123').isValid, isFalse);
    });

    test('a number with too many digits is invalid', () {
      expect(normalizePhoneForWhatsApp('+1234567890123456').isValid, isFalse);
    });

    test('a well-formed +-prefixed international number normalizes to digits only', () {
      final result = normalizePhoneForWhatsApp('+1 (555) 123-4567');
      expect(result.isValid, isTrue);
      expect(result.internationalDigits, '15551234567');
    });

    test('a 00-prefixed international number is treated the same as a +-prefixed one', () {
      final result = normalizePhoneForWhatsApp('0044 20 7946 0958');
      expect(result.isValid, isTrue);
      expect(result.internationalDigits, '442079460958');
    });

    test('formatting punctuation (spaces, dashes, parens) is stripped', () {
      final result = normalizePhoneForWhatsApp('+91-98765-43210');
      expect(result.internationalDigits, '919876543210');
    });
  });
}
