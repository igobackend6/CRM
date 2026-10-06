import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';
import 'app_typography.dart';

/// Material 3 theme built from the shared design tokens in
/// app_colors/app_typography/app_radius/app_shadows.dart — see
/// docs/design/design-tokens.md for where each value came from.
///
/// The overall `ColorScheme` is seeded from `AppColors.accent` (the
/// panel's own primary blue) so the algorithmically-generated supporting
/// roles (containers, outlines, surface tones — for which no single
/// token exists) stay on-brand rather than defaulting to Material's
/// generic purple; the roles we DO have an exact token for (accent/gold,
/// the real danger red, real surfaces/text) are then pinned via
/// `copyWith` so they're never left to the algorithm to guess. Component
/// themes below make sure every existing screen — none of which
/// hardcode a `Color(0x...)` outside this directory — inherits the new
/// look through `Theme.of(context)` alone.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.accent2 : AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      tertiary: AppColors.violet,
      error: AppColors.danger,
      surface: isDark ? AppColors.surfaceDark : AppColors.surface,
      onSurface: isDark ? AppColors.textHeadingDark : AppColors.textHeading,
      outline: isDark ? AppColors.borderDark : AppColors.border,
      outlineVariant: isDark ? AppColors.borderStrongDark : AppColors.borderStrong,
    );

    final textTheme = AppTypography.textTheme.apply(
      bodyColor: isDark ? AppColors.textHeadingDark : AppColors.textHeading,
      displayColor: isDark ? AppColors.textHeadingDark : AppColors.textHeading,
    );

    final background = isDark ? AppColors.backgroundDark : AppColors.background;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final hoverTint = isDark ? AppColors.hoverTintDark : AppColors.hoverTint;
    final secondaryText = isDark ? AppColors.textBodyDark : AppColors.textBody;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,

      // The brand-blue top bar (see `brandAppBar` for the gradient): white
      // title and icons, light status-bar icons. `backgroundColor` is the
      // solid fallback for any bar built without the gradient.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
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

      // The primary CTA: solid accent blue (a lighter blue in dark mode
      // so it isn't lost on a dark surface), 12px radius, 14px/w600 label.
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
      // A transparent secondary button: dark text/border.
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

      // White surface, 12px radius, a light neutral border.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: BorderSide(color: border),
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

      // 12px radius, subtle border, the brand's own blue tint for
      // selected chips.
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: hoverTint,
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
        color: border,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: secondaryText,
        textColor: colorScheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.textHeading,
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
