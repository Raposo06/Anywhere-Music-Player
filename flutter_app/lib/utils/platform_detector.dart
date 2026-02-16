import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Utility class to detect the current platform and form factor
class PlatformDetector {
  static const _channel = MethodChannel('com.anywhere.music_player/platform');

  /// Cached result of native TV detection
  static bool? _nativeTvResult;

  /// Fallback heuristic result
  static bool _isLikelyTV = false;

  /// Whether native detection has completed
  static bool _nativeDetectionDone = false;

  /// Check if running on Android TV
  static bool get isAndroidTV {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;

    // Use native result if available, otherwise fall back to heuristic
    if (_nativeDetectionDone && _nativeTvResult != null) {
      return _nativeTvResult!;
    }

    return _isLikelyTV;
  }

  /// Check if running on Windows
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Check if running on mobile (phone/tablet)
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Check if running on web
  static bool get isWeb => kIsWeb;

  /// Initialize TV detection using native platform channel.
  /// Call this from main() before runApp().
  static Future<void> initialize() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final isTV = await _channel.invokeMethod<bool>('isAndroidTV');
        _nativeTvResult = isTV ?? false;
        _nativeDetectionDone = true;
        debugPrint('TV detection (native): $_nativeTvResult');
      } catch (e) {
        debugPrint('Native TV detection failed, will use heuristic: $e');
        _nativeDetectionDone = true;
        _nativeTvResult = null;
      }
    }
  }

  /// Initialize TV detection with screen size (fallback heuristic).
  /// Call this from a widget with MediaQuery data.
  static void initializeWithScreenSize(double width, double height) {
    // Only use heuristic if native detection didn't produce a result
    if (_nativeTvResult != null) return;

    // TVs typically have large screens (>960dp) and are landscape
    _isLikelyTV = Platform.isAndroid &&
                  width > 960 &&
                  width > height;
  }
}
