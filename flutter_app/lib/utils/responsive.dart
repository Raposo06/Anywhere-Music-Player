import 'package:flutter/material.dart';

/// Breakpoints for responsive design
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wideDesktop = 1600;
}

/// Screen size categories
enum ScreenSize { mobile, tablet, desktop, wideDesktop }

/// Responsive utilities for adaptive layouts
class Responsive {
  /// Get current screen size category
  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < Breakpoints.mobile) return ScreenSize.mobile;
    if (width < Breakpoints.tablet) return ScreenSize.tablet;
    if (width < Breakpoints.desktop) return ScreenSize.desktop;
    return ScreenSize.wideDesktop;
  }

  /// Check if screen is mobile
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < Breakpoints.mobile;

  /// Check if screen is tablet or larger
  static bool isTabletOrLarger(BuildContext context) =>
      MediaQuery.of(context).size.width >= Breakpoints.mobile;

  /// Check if screen is desktop or larger
  static bool isDesktopOrLarger(BuildContext context) =>
      MediaQuery.of(context).size.width >= Breakpoints.tablet;

  /// Check if screen is wide desktop
  static bool isWideDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= Breakpoints.desktop;

  /// Get number of grid columns based on screen width
  static int getGridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < Breakpoints.mobile) return 1;
    if (width < Breakpoints.tablet) return 2;
    if (width < Breakpoints.desktop) return 3;
    if (width < Breakpoints.wideDesktop) return 4;
    return 5;
  }

  /// Get horizontal padding based on screen width
  static double getHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < Breakpoints.mobile) return 16;
    if (width < Breakpoints.tablet) return 24;
    if (width < Breakpoints.desktop) return 32;
    return 48;
  }

  /// Get content max width for centered layouts
  static double? getContentMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < Breakpoints.tablet) return null; // Full width on mobile/tablet
    return 1400; // Max width on desktop
  }
}

/// Responsive builder widget for conditional layouts
class ResponsiveBuilder extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = Responsive.getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.wideDesktop:
      case ScreenSize.desktop:
        return desktop ?? tablet ?? mobile;
      case ScreenSize.tablet:
        return tablet ?? mobile;
      case ScreenSize.mobile:
        return mobile;
    }
  }
}
