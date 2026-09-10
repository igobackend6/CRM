import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';
import 'app_typography.dart';

/// Material 3 theme built from the real Runo-derived tokens in
/// app_colors/app_typography/app_radius/app_shadows.dart — see
/// docs/design/design-tokens.md for where each value came from.
///
/// The overall `ColorScheme` is seeded from `AppColors.brandOrange` (the
/// literal logo color) so the algorithmically-generated supporting roles
/// (containers, outlines, surface tones — for which no single real value
/// exists) stay warm and on-brand rather than defaulting to Material's
/// generic blue; the handful of roles we DO have an exact real value for
/// (the CTA button's black, the real error red, real surfaces/text) are
/// then pinned via `copyWith` so they're never left to the algorithm to
/// guess. Component themes below make sure every existing screen — none
/// of which hardcode a `Color(0x...)` outside this directory — inherits
/// the new look through `Theme.of(context)` alone.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandOrange,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.brandOrange : AppColors.ctaBlack,
      onPrimary: isDark ? AppColors.textPrimary : Colors.white,
      secondary: AppColors.brandOrange,
      tertiary: AppColors.actionRed,
      error: AppColors.error,
      surface: isDark ? AppColors.surfaceDark : AppColors.surface,
      onSurface: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
      outline: isDark ? AppColors.borderDark : AppColors.border,
      outlineVariant: isDark ? AppColors.dividerDark : AppColors.divider,
    );

    final textTheme = AppTypography.textTheme.apply(
      bodyColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
      displayColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
    );

    final background = isDark ? AppColors.backgroundDark : AppColors.background;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final secondaryText = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          side: BorderSide(color: border),
        ),
      ),

      // The real "Start 10-day free trial" button: solid black (or the
      // brand orange in dark mode, so it isn't invisible on a dark
      // surface), 12px radius, 14px/w600 label.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: textTheme.labelLarge,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
        ),
      ),
      // The real "Book a Demo" secondary button: transparent, dark
      // text/border.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: colorScheme.onSurface),
      ),

      // The real `input.form-control`: white surface, 12px radius, a
      // light neutral border.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: secondaryText),
        hintStyle: textTheme.bodyMedium?.copyWith(color: secondaryText),
      ),

      // Feature-tile chips (`.feature-btn`): 12px radius, subtle border,
      // the warm `.active`-state tint for selected chips.
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.backgroundAlt,
        selectedColor: isDark ? AppColors.surfaceTintDark : AppColors.surfaceTint,
        labelStyle: textTheme.labelMedium,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // Language-switcher-style fully-rounded pill buttons/badges.
      badgeTheme: BadgeThemeData(
        backgroundColor: colorScheme.tertiary,
        textColor: Colors.white,
      ),

      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.dividerDark : AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: secondaryText,
        textColor: colorScheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: colorScheme.primary),
    );
  }
}

/// Re-exports the shadow tokens for widgets that need a raw `BoxShadow`
/// list (e.g. a custom `Container`/`DecoratedBox` outside the themed
/// component set) rather than duplicating `AppShadows` imports everywhere.
class AppElevation {
  AppElevation._();

  static const List<BoxShadow> floating = AppShadows.floating;
  static const List<BoxShadow> standard = AppShadows.standard;
  static const List<BoxShadow> small = AppShadows.small;
}
