class AppConstants {
  AppConstants._();

  static const String appName = 'Sales CRM';
  static const String flavorDefineKey = 'FLAVOR';

  /// Country code assumed for a phone number saved without one (India: the login screen also
  /// prefixes +91). Only used to open WhatsApp for such a number; nothing is stored with it.
  static const String defaultPhoneCountryCode = '91';
}
