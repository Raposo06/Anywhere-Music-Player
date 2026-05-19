import 'package:flutter/material.dart';

/// Responsive utilities for adaptive layouts
class Responsive {
  static const double _mobile = 600;
  static const double _tablet = 900;
  static const double _desktop = 1200;
  static const double _wideDesktop = 1600;

  static bool isDesktopOrLarger(BuildContext context) =>
      MediaQuery.of(context).size.width >= _tablet;

  static int getGridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < _mobile) return 1;
    if (width < _tablet) return 2;
    if (width < _desktop) return 3;
    if (width < _wideDesktop) return 4;
    return 5;
  }

  static double getHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < _mobile) return 16;
    if (width < _tablet) return 24;
    if (width < _desktop) return 32;
    return 48;
  }

  static double? getContentMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < _tablet) return null;
    return 1400;
  }
}
