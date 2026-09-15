import 'package:flutter/material.dart';

/// Color palette shared with the admin (web) panel's own design tokens —
/// see docs/design/design-tokens.md for the full token table and where
/// each value came from (2026-09-15 handoff). Kept token-for-token with
/// the panel's CSS custom properties so the two clients read as one
/// product, not two differently-branded apps. The web panel has no
/// dark theme, so the `*Dark` values are this app's own reasonable
/// extension of the same palette (kept close in hue, adjusted for
/// contrast on a dark surface), not a second real source.
class AppColors {
  AppColors._();

  // ---- brand hues ----

  /// `--accent` — primary blue: buttons, links, active nav.
  static const Color accent = Color(0xFF1D4ED8);

  /// `--accent-2` — lighter blue, gradient end.
  static const Color accent2 = Color(0xFF3B82F6);

  /// `--gold` — secondary brand gold.
  static const Color gold = Color(0xFFC6960C);

  // Distinct extra hues — named (not inlined) so call sites read as
  // intentional design-system choices, not magic hex. Shared by
  // [avatarPalette] below and any icon/category rail that needs more
  // than the two brand hues (e.g. activity_tile.dart's type colors).
  static const Color violet = Color(0xFF7C3AED);
  static const Color pink = Color(0xFFDB2777);
  static const Color sky = Color(0xFF0EA5E9);

  /// `--accent-bg` — blue tint background.
  static const Color accentBg = Color(0xFFEAF0FD);

  /// `--gold-bg` — gold tint background.
  static const Color goldBg = Color(0xFFFBF3DC);

  static const Color accentBgDark = Color(0xFF243049);

  /// `--gradient-brand`, 135deg.
  static const List<Color> gradientBrand = [accent, accent2];

  /// `--gradient-gold`, 135deg.
  static const List<Color> gradientGold = [gold, Color(0xFFE3B23C)];

  // Material3 seeds primary/secondary/tertiary directly off the brand
  // hues above rather than inventing a fourth — primary is the button/
  // active-nav color (what most Material components key off), secondary
  // is the brand's own secondary gold, tertiary is a third hue (violet)
  // for roles that need to stand apart from both blues.
  static const Color primary = accent;
  static const Color secondary = gold;
  static const Color tertiary = violet;

  // ---- text ----

  /// `--text-h` — headings.
  static const Color textHeading = Color(0xFF1F2430);

  /// `--text` — body.
  static const Color textBody = Color(0xFF4B5468);

  /// `--text-dim` — secondary.
  static const Color textDim = Color(0xFF8A93A6);

  static const Color textHeadingDark = Color(0xFFF5F6F8);
  static const Color textBodyDark = Color(0xFFC7CCD9);
  static const Color textDimDark = Color(0xFF8A93A6);

  // ---- surfaces ----

  /// `--bg` — page.
  static const Color background = Color(0xFFF5F6F8);

  /// `--bg-raised` — cards.
  static const Color surface = Color(0xFFFFFFFF);

  /// A pressed/selected-row tint — fixed to the brand's own blue tint
  /// (`--accent-bg`) rather than the web panel's current `--bg-hover`
  /// (`#FBEEE8`, a warm peach left over from Runo's old orange scheme,
  /// flagged 2026-09-15 as reading off against the blue everywhere
  /// else on that side) — this app never had that leftover, so it goes
  /// straight to the corrected value instead of copying the bug.
  static const Color hoverTint = accentBg;

  static const Color backgroundDark = Color(0xFF14171F);
  static const Color surfaceDark = Color(0xFF1E2330);
  static const Color hoverTintDark = accentBgDark;

  // ---- borders ----

  static const Color border = Color(0xFFE7E9EE);
  static const Color borderStrong = Color(0xFFD8DCE4);

  static const Color borderDark = Color(0xFF333A4A);
  static const Color borderStrongDark = Color(0xFF454E62);

  // ---- status ----

  static const Color success = Color(0xFF2E9E5B);
  static const Color successBg = Color(0xFFE8F7EE);

  static const Color danger = Color(0xFFE53935);
  static const Color dangerBg = Color(0xFFFDECEA);

  /// `--warning` is the same colour as [gold] by design on the web
  /// panel — reused here rather than redeclared.
  static const Color warning = gold;
  static const Color warningBg = goldBg;

  static const Color cold = Color(0xFF64748B);
  static const Color coldBg = Color(0xFFF1F5F9);

  /// A distinct "high priority" hue, deliberately kept apart from
  /// [gold]/[warning]. Flagged 2026-09-15: the web panel's
  /// `--accent-pink` (used for "high priority" in the funnel chart) is
  /// currently identical to `--gold`, so a high-priority segment renders
  /// the same colour as the medium one beside it. This app has no
  /// priority-color mapping yet, but should reach for this rather than
  /// [gold]/[warning] if/when one is added.
  static const Color highPriority = pink;

  /// Cycled by id (a deterministic hash, not random — see
  /// InitialsAvatar) for avatars, and any other "distinct color per
  /// item" need such as activity_tile.dart's per-type icon rail.
  static const List<Color> avatarPalette = [accent, gold, success, violet, pink, sky];
}
