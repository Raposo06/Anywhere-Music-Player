import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Font family names as declared in `pubspec.yaml`.
///
/// The handoff splits type by role rather than by size: Work Sans for
/// everything you scan (labels, counts, buttons), Source Serif 4 for the
/// things that are *named* — screen titles and track/folder names. Keeping
/// both here means a call site says which role it is, not which file to load.
abstract final class AppFonts {
  /// UI text: labels, buttons, counts, metadata.
  static const ui = 'WorkSans';

  /// Titles and track names.
  static const serif = 'SourceSerif4';
}

/// The hand cursor every clickable thing in this app uses.
///
/// **Load-bearing — do not delete as redundant.** Material's buttons default
/// their cursor to `WidgetStateMouseCursor.adaptiveClickable`, which resolves
/// to `kIsWeb ? click : basic` — so on desktop *every* Material button
/// deliberately shows the plain arrow, copying the native macOS/Windows
/// convention that a hand means a hyperlink. This app wants the hand
/// everywhere clickable, matching what `HoverRow` already does for rows, so
/// each button theme below opts in explicitly. Remove these and the buttons
/// silently go back to an arrow while the rows keep their hand.
const pointerCursor = SystemMouseCursors.click;

/// The redesign theme — a warm off-black ramp with a single teal accent.
///
/// Applied on every platform (phone, Android TV, desktop) so the app looks
/// like one product; only the *layout* differs by form factor. Replaces the
/// former navy/amber "PS1 classic" theme.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentStrong,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.accentText,
    onSecondary: Colors.black,
    tertiary: AppColors.accentStrong,
    onTertiary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerLowest: AppColors.background,
    surfaceContainerLow: AppColors.win,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surface,
    surfaceContainerHighest: AppColors.surface2,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    error: AppColors.destructive,
    onError: Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppFonts.ui,
    scaffoldBackgroundColor: AppColors.background,
  );

  return base.copyWith(
    // Titles use the serif; everything else stays on Work Sans (inherited
    // from `fontFamily` above). Sizes track the handoff's type scale.
    textTheme: base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontFamily: AppFonts.serif,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontFamily: AppFonts.serif,
      ),
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontFamily: AppFonts.serif,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontFamily: AppFonts.serif,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontFamily: AppFonts.serif,
        fontSize: 34,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontFamily: AppFonts.serif,
        fontSize: 26,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontFamily: AppFonts.serif,
        fontWeight: FontWeight.w600,
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.serif,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    ),

    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.muted,
      textColor: AppColors.text,
      selectedColor: AppColors.accentText,
      selectedTileColor: AppColors.accentSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),

    iconTheme: const IconThemeData(color: AppColors.muted),

    // Filled pill: "Play All", and the login button.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        enabledMouseCursor: pointerCursor,
        disabledMouseCursor: SystemMouseCursors.basic,
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
      ),
    ),

    // Outline pill: "Shuffle".
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        enabledMouseCursor: pointerCursor,
        disabledMouseCursor: SystemMouseCursors.basic,
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentText,
        enabledMouseCursor: pointerCursor,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        enabledMouseCursor: pointerCursor,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        enabledMouseCursor: pointerCursor,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),

    // Pill-shaped search field, per the handoff (20px full-round).
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: TextStyle(color: AppColors.faint, fontSize: 13),
      prefixIconColor: AppColors.faint,
      suffixIconColor: AppColors.faint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
      labelStyle: TextStyle(color: AppColors.muted),
    ),

    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.surface2,
      thumbColor: AppColors.accent,
      overlayColor: AppColors.accentSoft,
      trackHeight: 4,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.surface2,
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.faint,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accentSoft,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.faint,
        ),
      ),
    ),

    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: TextStyle(
        color: AppColors.text,
        fontFamily: AppFonts.ui,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
    ),

    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),

    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(color: AppColors.text, fontSize: 12),
    ),
  );
}
