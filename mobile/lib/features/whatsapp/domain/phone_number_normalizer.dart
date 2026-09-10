/// Result of normalizing a lead's raw phone number into the format a
/// `wa.me` WhatsApp deep link needs (§6 "detect valid lead phone
/// number" / "normalize phone number appropriately"): digits only, no
/// leading `+`/`00`/spaces/dashes, always including a country code.
class PhoneNormalizationResult {
  const PhoneNormalizationResult.valid(this.internationalDigits) : isValid = true;

  const PhoneNormalizationResult.invalid()
      : isValid = false,
        internationalDigits = null;

  final bool isValid;
  final String? internationalDigits;
}

/// A `wa.me` link requires the FULL international number (country code
/// + subscriber number, no leading zero, no separators) — there is no
/// reliable way to tell a bare local number apart from one that already
/// includes a country code without a `+`/`00` prefix to anchor on, and
/// guessing a default country would silently send messages to the
/// wrong number in another country's numbering plan. So this only
/// accepts numbers that are unambiguous: prefixed with `+` or `00`,
/// and 8-15 digits long after normalization (E.164's own bounds).
/// Anything else (missing, too short/long, no country-code marker) is
/// reported invalid rather than guessed at.
PhoneNormalizationResult normalizePhoneForWhatsApp(String? rawPhone) {
  if (rawPhone == null) return const PhoneNormalizationResult.invalid();
  var value = rawPhone.trim();
  if (value.isEmpty) return const PhoneNormalizationResult.invalid();

  if (value.startsWith('00')) {
    value = '+${value.substring(2)}';
  }
  final hasCountryCodeMarker = value.startsWith('+');
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

  if (!hasCountryCodeMarker) return const PhoneNormalizationResult.invalid();
  if (digits.length < 8 || digits.length > 15) return const PhoneNormalizationResult.invalid();

  return PhoneNormalizationResult.valid(digits);
}
