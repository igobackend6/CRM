import 'package:flutter/material.dart';

/// Type scale built on Inter (the real, confirmed typeface — see
/// docs/design/design-tokens.md's `--default-font` note), keeping the
/// weight language Runo actually uses (700/600 for emphasis, 500-600 for
/// buttons/labels, 400 for body) at sizes appropriate to a phone screen
/// rather than the marketing site's own hero-banner pixel sizes (its
/// h1 is 45px — unusable on a phone). Screen-level layout decisions
/// still belong to individual features, not this file.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Inter';

  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(fontFamily: fontFamily, fontSize: 34, fontWeight: FontWeight.w700, height: 40 / 34),
    displayMedium: TextStyle(fontFamily: fontFamily, fontSize: 28, fontWeight: FontWeight.w700, height: 34 / 28),
    displaySmall: TextStyle(fontFamily: fontFamily, fontSize: 24, fontWeight: FontWeight.w700, height: 30 / 24),

    headlineLarge: TextStyle(fontFamily: fontFamily, fontSize: 24, fontWeight: FontWeight.w700, height: 28.8 / 24),
    headlineMedium: TextStyle(fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w700, height: 24 / 20),
    headlineSmall: TextStyle(fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600, height: 22 / 18),

    titleLarge: TextStyle(fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w700, height: 24 / 20),
    titleMedium: TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600, height: 19.2 / 16),
    titleSmall: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600, height: 20 / 15),

    bodyLarge: TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w400, height: 24 / 16),
    bodyMedium: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14),
    bodySmall: TextStyle(fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12),

    labelLarge: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600, height: 20 / 14),
    labelMedium: TextStyle(fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w600, height: 16 / 12),
    labelSmall: TextStyle(fontFamily: fontFamily, fontSize: 11, fontWeight: FontWeight.w500, height: 14 / 11),
  );
}
