/// The phone permission Connected SIM Details needs (READ_PHONE_STATE).
enum SimPermissionStatus {
  granted,

  /// Never asked on this install — the system dialog can be shown.
  notRequested,

  /// Refused, but Android will still show the dialog again.
  denied,

  /// Refused for good — only the app's page in Android Settings can allow it now.
  permanentlyDenied,

  /// No SIM support on this device/platform (a Wi-Fi tablet, or not Android).
  unavailable;

  static SimPermissionStatus fromPlatform(Object? value) => switch (value) {
        'granted' => granted,
        'notRequested' => notRequested,
        'denied' => denied,
        'permanentlyDenied' => permanentlyDenied,
        'unavailable' => unavailable,
        // Unknown answer: treat as not allowed, so the screen offers the permission flow.
        _ => denied,
      };
}
