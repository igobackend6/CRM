# Design tokens — Runo-inspired visual design

This document records the exact, real design tokens the mobile app's visual
design (Flutter theme in `mobile/lib/core/theme/`) is built from, and where
each one came from. It exists so the tokens in code are traceable and
auditable, not invented or eyeballed from memory.

**Source**: live inspection of `https://runo.ai` (the public marketing site
for Runo, a SIM-based call-management CRM) on 2026-09-03, via
`getComputedStyle()` on the real rendered DOM and the site's own CSS custom
properties — not a redraw from screenshots. Every value below is quoted
exactly as extracted; where a screenshot-only observation was used instead
(because a value wasn't reachable in the live DOM — see the AVIF note below),
it's marked **(visual estimate)**.

A note on scope: this reproduces a *visual language* (colors, type scale,
radii, shadows, spacing rhythm) — not Runo's logo, wordmark, copy, imagery,
or product screens. `mobile/lib/core/theme/app_colors.dart` previously
carried a comment saying the palette was "not derived from or matching any
third-party CRM's visual identity" — that was true of the Phase 3
placeholder theme it described; this document supersedes it.

## Methodology note: AVIF decoding

The site's actual in-app screenshots (phone/browser mockups) are served as
`.avif` images. This environment's Chromium build fails to `drawImage()`/
`getImageData()` the top ~150px of at least one of those files (returns
transparent pixels for that region only, both via `<img>`+canvas and
`createImageBitmap()`, with or without a CORS-safe `blob:` URL) — a decoder
bug in this specific environment, not a real property of the image. Where a
token could only be read from that region, it's a **(visual estimate)** from
the screenshot instead of a sampled pixel value, called out explicitly below.

## Color

| Token | Value | Source |
|---|---|---|
| `brandOrange` | `#FF5730` | Logo SVG `<path fill="#FF5730">` (the runo icon mark) |
| `brandInk` | `#293345` | Logo SVG secondary path fill (wordmark detail) |
| `actionRed` | `#F44336` | Computed `background-color` of the visible "Start 10-day free trial" *icon accents* (app-store link icons) — `color: rgb(244, 67, 54)` |
| `ctaBlack` | `#000000` | Computed `background-color` of `.btn-default-dark.btn-highlighted` — the actual highest-emphasis button ("Start 10-day free trial", "Request a Demo") |
| `textPrimary` | `#111111` | Computed `color` of `h1`–`h5` |
| `textSecondary` | `#303030` | Computed `color` of nav links / "Login" |
| `textTertiary` | `#252525` | Computed `color` of dropdown nav items |
| `surface` | `#FFFFFF` | Computed `background-color` of cards/inputs |
| `surfaceTint` | `#FCF6F5` | Computed `background-color` of a feature tile's `.active` state (a warm, barely-there tint) |
| `background` | `#FAFAFA` | Computed `background-color` of `.features-section` |
| `backgroundAlt` | `#F9F9F9` | Computed `background-color` of `.feature-btn` tiles |
| `border` | `#DDDDDD` | Computed `border-color` of `.feature-btn` |
| `inputBorder` | `#DEE2E6` | Computed `border-color` of `input.form-control` |
| `divider` | `rgba(59,84,80,0.14)` | CSS custom property `--divider-color: #3b545024` |
| `error` | `#E65757` | CSS custom property `--error-color: rgb(230,87,87)` |
| `accentGradient` | `linear-gradient(93.43deg, #FF5730 -4.63%, #5E33EC 65.52%, #0065F2 106.84%)` | CSS custom property `--accent-secondary-color` |

`accentGradient` (orange → violet → blue) is the site's "AI-powered" accent
— used sparingly in the app for genuinely notable moments (e.g. an
empty-state or a subtle highlight), never as a primary UI color; this app
has no AI features to badge with it yet.

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
