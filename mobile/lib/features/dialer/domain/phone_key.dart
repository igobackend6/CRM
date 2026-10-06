/// The last 10 digits of a phone number, or null when it has fewer than 10 digits.
///
/// The one rule used everywhere numbers are compared (the server's lead matching, call sync, and the
/// dialer): `+91 98765 43210`, `919876543210`, `09876543210` and `9876543210` are the same person.
String? phoneKey(String? number) {
  if (number == null) return null;
  final digits = number.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 10 ? digits.substring(digits.length - 10) : null;
}
