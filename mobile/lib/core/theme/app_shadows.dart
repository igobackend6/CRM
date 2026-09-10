import 'package:flutter/material.dart';

/// Shadow presets — see docs/design/design-tokens.md. Flutter's
/// `BoxShadow` doesn't support an inset shadow, so `floating`'s inset
/// highlight (real value: `inset 0 1px 0 rgba(255,255,255,.95)`) is
/// dropped rather than faked; the outer shadow is kept as-is.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x1F0F172A), offset: Offset(0, 12), blurRadius: 28),
  ];

  static const List<BoxShadow> standard = [
    BoxShadow(color: Color(0x26000000), offset: Offset(0, 8), blurRadius: 16),
  ];

  static const List<BoxShadow> small = [
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 6),
  ];
}
