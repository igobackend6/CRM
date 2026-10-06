import '../../../core/constants/app_constants.dart';
import '../../whatsapp/domain/phone_number_normalizer.dart';

/// Normalizes a SIM mobile number the employee typed into E.164 (`+91XXXXXXXXXX`), or null when it
/// isn't a usable number. A bare 10-digit number (optionally with a leading 0) is read as Indian,
/// the same rule the rest of the app uses.
String? normalizeSimNumber(String raw) {
  final result = normalizePhoneForWhatsApp(raw, defaultCountryCode: AppConstants.defaultPhoneCountryCode);
  return result.isValid ? '+${result.internationalDigits}' : null;
}
