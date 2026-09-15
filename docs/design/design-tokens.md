# Design tokens — shared with the admin (web) panel

This document records the exact design tokens the mobile app's visual design
(Flutter theme in `mobile/lib/core/theme/`) is built from, and where each one
came from. It exists so the tokens in code are traceable and auditable, not
invented or eyeballed from memory.

**Source (current)**: the admin (web) panel's own CSS custom properties, handed
off 2026-09-15 so the two clients read as one product rather than two
differently-branded apps — see the color table below. `AppColors` in
`mobile/lib/core/theme/app_colors.dart` is kept token-for-token with these.

**Source (superseded)**: this document previously derived the palette from
live inspection of `https://runo.ai` (a SIM-based call-management CRM used
only as a visual-language reference, not this product's brand) on 2026-09-03.
That palette (`brandOrange`/`brandInk`/`actionRed`/`ctaBlack`/`accentGradient`,
etc.) has been fully replaced by the admin-panel tokens below — kept in git
history, not reproduced here, since none of it is live in code anymore.
Type scale, radii, shadows, and spacing rhythm below are still the Runo-derived
values; only color has switched source so far.

## Color

| Token | Value | Notes |
|---|---|---|
| `accent` | `#1D4ED8` | Primary blue — buttons, links, active nav |
| `accent2` | `#3B82F6` | Lighter blue, gradient end |
| `accentBg` | `#EAF0FD` | Blue tint background |
| `gold` | `#C6960C` | Secondary brand gold |
| `goldBg` | `#FBF3DC` | Gold tint background |
| `gradientBrand` | `135deg, #1D4ED8 → #3B82F6` | |
| `gradientGold` | `135deg, #C6960C → #E3B23C` | |
| `violet` / `pink` / `sky` | `#7C3AED` / `#DB2777` / `#0EA5E9` | Extra distinct hues — avatar cycle, activity-type icon rail |
| `textHeading` | `#1F2430` | Headings |
| `textBody` | `#4B5468` | Body |
| `textDim` | `#8A93A6` | Secondary |
| `background` | `#F5F6F8` | Page |
| `surface` | `#FFFFFF` | Cards |
| `border` | `#E7E9EE` | |
| `borderStrong` | `#D8DCE4` | |
| `success` / `successBg` | `#2E9E5B` / `#E8F7EE` | |
| `danger` / `dangerBg` | `#E53935` / `#FDECEA` | |
| `warning` / `warningBg` | `#C6960C` / `#FBF3DC` | Same value as `gold`/`goldBg` by design |
| `cold` / `coldBg` | `#64748B` / `#F1F5F9` | |
| `avatarPalette` | `#1D4ED8 · #C6960C · #2E9E5B · #7C3AED · #DB2777 · #0EA5E9` | Cycled by id |

Two corrections made relative to the web panel's current state, flagged by the
admin during the 2026-09-15 handoff:

- **`highPriority`** (`#DB2777`, the `pink` hue) is a deliberately distinct
  color, kept apart from `gold`/`warning`. The web panel's `--accent-pink` is
  currently identical to `--gold`, so a high-priority segment renders the same
  color as "medium" right beside it in its funnel chart — a flagged bug. This
  app has no priority-color mapping yet, but should reach for `highPriority`
  rather than `gold`/`warning` if one is added, so it never reproduces that
  collision.
- **`hoverTint`** is fixed to `accentBg` (the brand's own blue tint) rather
  than the web panel's current `--bg-hover` (`#FBEEE8`, a warm peach left over
  from Runo's old orange scheme — the one place that palette survived there,
  and it reads slightly off against the blue everywhere else). This app never
  had that leftover, so it goes straight to the corrected value.

`*Dark` variants (`backgroundDark`, `surfaceDark`, `textHeadingDark`, etc.) are
this app's own reasonable extension of the same palette for its dark theme —
the admin panel has no dark theme, so these aren't a second real source, just
kept close in hue and adjusted for contrast on a dark surface.

## Typography

Real family: **Inter** (CSS custom property `--default-font: 'Inter',sans-serif`,
confirmed on `body`, headings, buttons, nav — bundled locally in
`mobile/assets/fonts/Inter.ttf`, a variable-weight font, rather than fetched
at runtime, since this app must work for field reps without reliable
connectivity).

Real weight/size pairs read from the live site (marketing-page pixel sizes,
not directly usable on a phone screen — see "Adaptation" below):

| Element | Size | Weight | Line height |
|---|---|---|---|
| `h1` | 45px | 200 | 54px |
| `h2` | 25px | 200 | 30px |
| `h3` | 15px | 600 | 22.5px |
| `h4` | 24px | 700 | 28.8px |
| `h5` | 20px | 700 | 24px |
| `h6` | 16px | 600 | 19.2px |
| body `p` | 16px | 400 | 27.2px |
| primary button (`.btn-default-dark`) | 14px | 600 | — |
| header button (`.header-btn-dark`) | 16px | 500 | — |
| nav link | 16px | 500 | — |
| feature-tile label | 10px | 500 | — |

**Adaptation for a phone-sized app**: the marketing site's display sizes
(45px/25px h1/h2) are hero-banner scale and not appropriate for in-app
headings. `AppTypography` keeps the *weight language* Runo actually uses
(700/600 for strong emphasis, 500 for buttons/labels, 400 for body) at sizes
that fit Material 3's `TextTheme` roles on a phone.

## Shape

| Token | Value | Source |
|---|---|---|
| `radius` (standard) | 12px | `.btn-default-dark`, `.btn-plain-dark`, `.feature-btn`, `input.form-control` — the one radius used almost everywhere on the site |
| `radiusPill` | 9999px | `.rt-lang-btn` (language switcher), avatar-style circular buttons |
| `radiusHover` | 16px | Nav dropdown item hover state |

## Elevation / shadow

| Token | Value | Source |
|---|---|---|
| `shadowFloating` | `0 12px 28px rgba(15,23,42,.12), inset 0 1px 0 rgba(255,255,255,.95)` | `.rt-lang-btn` — a soft floating shadow with an inset top highlight |
| `shadowStandard` | `0 8px 16px rgba(0,0,0,.15)` | site-wide `--bs-box-shadow` |
| `shadowSmall` | `0 2px 6px rgba(0,0,0,.1)` | circular nav buttons (testimonial prev/next) |

## Applied in code

- `mobile/lib/core/theme/app_colors.dart` — the color table above
- `mobile/lib/core/theme/app_typography.dart` — the adapted type scale
- `mobile/lib/core/theme/app_radius.dart` — the shape tokens
- `mobile/lib/core/theme/app_shadows.dart` — the elevation tokens
- `mobile/lib/core/theme/app_theme.dart` — assembles all of the above into
  Material 3 `ThemeData` (light/dark), including component themes
  (`ElevatedButtonThemeData`, `FilledButtonThemeData`, `OutlinedButtonThemeData`,
  `CardThemeData`, `ChipThemeData`, `InputDecorationThemeData`, `AppBarTheme`,
  `BadgeThemeData`) so every existing screen picks up the new look through
  `Theme.of(context)` without per-screen edits — the app already has zero
  hardcoded `Color(0x...)`/`Colors.*` usage outside `core/theme/`.
