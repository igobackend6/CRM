import 'package:flutter/material.dart';

/// Color palette extracted from the real, live Runo CRM marketing site
/// (`https://runo.ai`) — see docs/design/design-tokens.md for the exact
/// selector/property each value was read from via `getComputedStyle()`,
/// not eyeballed from a screenshot. Runo has no public dark theme, so the
/// `*Dark` values are this app's own reasonable extension of the same
/// palette (kept close in hue, adjusted for contrast on a dark surface),
/// not a second real source.
class AppColors {
  AppColors._();

  // ---- brand ----

  /// The runo logo mark's own SVG fill.
  static const Color brandOrange = Color(0xFFFF5730);

  /// The logo wordmark's secondary ink color.
  static const Color brandInk = Color(0xFF293345);

  /// Icon-accent red-orange (app-store link icons on the marketing site).
  static const Color actionRed = Color(0xFFF44336);

  /// The real highest-emphasis button color site-wide
  /// (`.btn-default-dark.btn-highlighted` — "Start 10-day free trial").
  static const Color ctaBlack = Color(0xFF000000);

  // Material3 seeds primary/secondary/tertiary off the three brand hues
  // above rather than inventing a fourth — primary is the button color
  // (what most Material components key off), secondary/tertiary are the
  // brand accents.
  static const Color primary = ctaBlack;
  static const Color primaryLight = brandInk;
  static const Color secondary = brandOrange;
  static const Color tertiary = actionRed;

  // ---- surfaces ----

  static const Color background = Color(0xFFFAFAFA);
  static const Color backgroundAlt = Color(0xFFF9F9F9);
  static const Color surface = Color(0xFFFFFFFF);

  /// A feature tile's `.active` state — a barely-there warm tint, used
  /// here for a selected/highlighted list row or chip background.
  static const Color surfaceTint = Color(0xFFFCF6F5);

  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color surfaceTintDark = Color(0xFF2A2220);

  // ---- text ----

  static const Color textPrimary = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF303030);
  static const Color textTertiary = Color(0xFF6C757D);

  static const Color textPrimaryDark = Color(0xFFF5F5F5);
  static const Color textSecondaryDark = Color(0xFFC7C7C7);
  static const Color textTertiaryDark = Color(0xFF9A9A9A);

  // ---- borders ----

  static const Color border = Color(0xFFDDDDDD);
  static const Color inputBorder = Color(0xFFDEE2E6);
  static const Color divider = Color(0x243B5450); // --divider-color

  static const Color borderDark = Color(0xFF3A3A3A);
  static const Color dividerDark = Color(0x40C7C7C7);

  // ---- status ----

  static const Color success = Color(0xFF198754);
  static const Color warning = Color(0xFFC77700);
  static const Color error = Color(0xFFE65757); // --error-color

  /// AI/premium accent gradient — `--accent-secondary-color`. Use
  /// sparingly (an empty state, a single highlight), never as a base UI
  /// color.
  static const List<Color> accentGradient = [Color(0xFFFF5730), Color(0xFF5E33EC), Color(0xFF0065F2)];
}
