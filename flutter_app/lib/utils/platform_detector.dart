import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Utility class to detect the current platform and form factor
class PlatformDetector {
  /// Check if running on Android TV
  /// Note: This is a heuristic - for accurate detection, use platform channels
  /// to check for LEANBACK feature or TV UI mode
  static bool get isAndroidTV {
    if (kIsWeb) return false;

    // TODO: Implement native platform channel to check for:
    // - android.software.leanback feature
    // - Configuration.UI_MODE_TYPE_TELEVISION
    // For now, we'll use screen size heuristics

    return Platform.isAndroid && _isLikelyTV;
  }

  /// Check if running on Windows
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Check if running on mobile (phone/tablet)
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Check if running on web
  static bool get isWeb => kIsWeb;

  /// Heuristic: Large screens in landscape are likely TVs
  /// This should be replaced with proper platform channel detection
  static bool _isLikelyTV = false;

  /// Initialize TV detection with screen size
  /// Call this from main() after runApp() with MediaQuery data
  static void initializeWithScreenSize(double width, double height) {
    // TVs typically have large screens (>960dp) and are landscape
    _isLikelyTV = Platform.isAndroid &&
                  width > 960 &&
                  width > height;
  }
}
