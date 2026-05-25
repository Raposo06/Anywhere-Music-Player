import 'dart:ffi';
import 'package:flutter/foundation.dart';

/// Keeps the system awake while music is playing on Windows, without keeping
/// the display on — mirrors MusicBee / Windows Media Player behavior (the
/// monitor can still turn off, but the PC won't suspend).
///
/// Uses the Win32 `SetThreadExecutionState` API. Passing `ES_SYSTEM_REQUIRED`
/// together with `ES_CONTINUOUS` makes the request persist until it's cleared;
/// passing `ES_CONTINUOUS` alone clears it and lets the normal idle-sleep timer
/// resume. We deliberately omit `ES_DISPLAY_REQUIRED` so the screen can sleep.
class WindowsWakelock {
  WindowsWakelock._();

  static const int _esContinuous = 0x80000000;
  static const int _esSystemRequired = 0x00000001;

  static bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  // Resolved once. Null on non-Windows or if the lookup fails.
  static final int Function(int)? _setThreadExecutionState = _resolve();

  static int Function(int)? _resolve() {
    if (!_isSupported) return null;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      return kernel32
          .lookupFunction<Uint32 Function(Uint32), int Function(int)>(
        'SetThreadExecutionState',
      );
    } catch (e) {
      debugPrint('WindowsWakelock: failed to load SetThreadExecutionState: $e');
      return null;
    }
  }

  static bool _active = false;

  /// Prevent the system from sleeping (the display may still turn off).
  /// Idempotent — safe to call repeatedly.
  static void enable() {
    if (_active) return;
    final fn = _setThreadExecutionState;
    if (fn == null) return;
    fn(_esContinuous | _esSystemRequired);
    _active = true;
  }

  /// Allow the system to sleep normally again. Idempotent.
  static void disable() {
    if (!_active) return;
    final fn = _setThreadExecutionState;
    if (fn == null) return;
    fn(_esContinuous);
    _active = false;
  }
}
