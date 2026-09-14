import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/domain/login_phone_normalizer.dart';

void main() {
  group('normalizeLoginPhone', () {
    test('bare 10 digits gets +91', () {
      expect(normalizeLoginPhone('9876543210'), '+919876543210');
    });

    test('formatted 10 digits (spaces/dashes) gets +91', () {
      expect(normalizeLoginPhone('98765 43210'), '+919876543210');
      expect(normalizeLoginPhone('98765-43210'), '+919876543210');
    });

    test('already carries a country code -> just prefixed with +, no extra 91', () {
      expect(normalizeLoginPhone('+919876543210'), '+919876543210');
      expect(normalizeLoginPhone('919876543210'), '+919876543210');
      expect(normalizeLoginPhone('+14155552671'), '+14155552671');
    });
  });
}
