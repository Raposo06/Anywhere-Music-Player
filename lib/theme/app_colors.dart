import 'package:flutter/material.dart';

/// The redesign's colour tokens, converted from the OKLCH values in the
/// design handoff (`design_handoff_desktop_redesign/README.md`).
///
/// The handoff specifies every colour in OKLCH and asks for a direct
/// conversion rather than an eyeballed approximation, so these were computed
/// through the OKLab → linear sRGB → sRGB pipeline and are recorded here as
/// the single source of truth. The OKLCH original is kept in a comment beside
/// each one: that's what a future tweak should be edited against, since
/// nudging the hex by hand will not stay on the intended lightness/chroma
/// ramp.
///
/// A warm off-black ramp (hue ~45°) carries the surfaces; a single teal
/// accent (hue 200°) carries everything interactive.
abstract final class AppColors {
  /// Window body behind the sidebar + content. `oklch(0.17 0.013 45)`
  static const win = Color(0xFF140E0B);

  /// App/scaffold background, one step darker than [win].
  /// `oklch(0.15 0.012 45)`
  static const background = Color(0xFF100A07);

  /// Sidebar, cards, mini player, panels. `oklch(0.22 0.014 45)`
  static const surface = Color(0xFF201915);

  /// Hover fills, art placeholders, slider tracks. `oklch(0.27 0.015 45)`
  static const surface2 = Color(0xFF2D2420);

  /// Hairline dividers and outlines. `oklch(0.34 0.016 45 / 0.5)`
  static const border = Color(0x803F3531);

  /// Primary text. `oklch(0.95 0.006 50)`
  static const text = Color(0xFFF2EDEB);

  /// Secondary text — artist, counts, durations. `oklch(0.68 0.012 50)`
  static const muted = Color(0xFF9F9692);

  /// Tertiary text — section labels, placeholders. `oklch(0.5 0.012 50)`
  static const faint = Color(0xFF69615D);

  /// The one accent hue: play buttons, active icons, fills.
  /// `oklch(0.68 0.15 200)`
  static const accent = Color(0xFF00B2BD);

  /// Pressed/emphasis accent. `oklch(0.58 0.16 200)`
  static const accentStrong = Color(0xFF00949F);

  /// Active-row and active-pill fill. `oklch(0.68 0.15 200 / 0.16)`
  static const accentSoft = Color(0x2900B2BD);

  /// Accent *text* — lighter than [accent] so it stays readable at body
  /// sizes on [surface]. `oklch(0.8 0.11 200)`
  static const accentText = Color(0xFF56D3DA);

  /// Custom window chrome, darker than every other surface.
  /// `oklch(0.13 0.011 45)`
  static const titlebar = Color(0xFF0B0605);

  /// Close-button hover. `oklch(0.55 0.2 25)`
  static const destructive = Color(0xFFCC272E);

  /// The accent glow under the play button. `oklch(0.68 0.15 200 / 0.55)`
  static const accentGlow = Color(0x8C00B2BD);
}

/// Shadows from the handoff. CSS spreads a shadow with a negative fourth
/// value (spread); Flutter's equivalent is `spreadRadius`, and CSS's blur is
/// roughly twice Flutter's `blurRadius`, so the conversions below are
/// deliberately eyeball-matched rather than arithmetic.
abstract final class AppShadows {
  /// `0 30px 70px -25px oklch(0 0 0 / 0.7)` — the floating window frame.
  static const window = <BoxShadow>[
    BoxShadow(
      color: Color(0xB3000000),
      blurRadius: 35,
      spreadRadius: -12,
      offset: Offset(0, 15),
    ),
  ];

  /// `0 20px 45px -18px oklch(0 0 0 / 0.6)` — the mini player bar.
  static const miniPlayer = <BoxShadow>[
    BoxShadow(
      color: Color(0x99000000),
      blurRadius: 22,
      spreadRadius: -9,
      offset: Offset(0, -4),
    ),
  ];

  /// `0 8px 24px -4px oklch(0.68 0.15 200 / 0.55)` — under the round accent
  /// play button.
  static const accentGlow = <BoxShadow>[
    BoxShadow(
      color: AppColors.accentGlow,
      blurRadius: 12,
      spreadRadius: -2,
      offset: Offset(0, 4),
    ),
  ];

  /// `0 25px 50px -12px oklch(0 0 0 / 0.5)` — under the Now Playing art.
  static const albumArt = <BoxShadow>[
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 25,
      spreadRadius: -6,
      offset: Offset(0, 12),
    ),
  ];
}

/// Fixed metrics the desktop layout is specified in. Sizes that only appear
/// once live at their use site; these are the ones two or more widgets have
/// to agree on.
abstract final class AppMetrics {
  static const double titlebarHeight = 40;
  static const double sidebarWidth = 224;
  static const double upNextWidth = 300;
  static const double miniPlayerHeight = 72;

  /// Hover/press feedback, per the handoff's "subtle, fast" note.
  static const Duration stateTransition = Duration(milliseconds: 130);
}
