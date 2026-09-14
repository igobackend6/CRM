/// Normalizes the login screen's mobile-number field into the E.164
/// form `auth.users.phone` is keyed on, mirroring the admin panel's own
/// rule exactly (bare 10 digits are assumed Indian; anything longer is
/// taken as already carrying a country code): strip everything but
/// digits, then a 10-digit result gets `+91`, anything else just `+`.
String normalizeLoginPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 10) return '+91$digits';
  return '+$digits';
}
