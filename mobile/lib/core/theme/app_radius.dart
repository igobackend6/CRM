/// Corner-radius scale — see docs/design/design-tokens.md. Runo uses one
/// radius (12px) almost everywhere (buttons, cards, tiles, inputs), a
/// larger one only for nav-dropdown hover states, and a fully-rounded
/// pill for badges/circular icon buttons.
class AppRadius {
  AppRadius._();

  static const double standard = 12;
  static const double hover = 16;
  static const double pill = 9999;
}
