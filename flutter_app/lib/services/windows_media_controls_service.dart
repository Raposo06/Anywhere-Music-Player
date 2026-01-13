import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';
import '../models/track.dart';

/// Service to handle Windows System Media Transport Controls
/// This enables taskbar thumbnail controls (play/pause, next, prev)
class WindowsMediaControlsService {
  static WindowsMediaControlsService? _instance;
  SMTCWindows? _smtc;
  bool _isInitialized = false;

  // Callbacks for button presses
  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  VoidCallback? onStop;

  WindowsMediaControlsService._();

  static WindowsMediaControlsService get instance {
    _instance ??= WindowsMediaControlsService._();
    return _instance!;
  }

  /// Check if we're running on Windows
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Initialize the Windows media controls
  Future<void> initialize({
    VoidCallback? onPlay,
    VoidCallback? onPause,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    VoidCallback? onStop,
  }) async {
    if (!isSupported || _isInitialized) return;

    this.onPlay = onPlay;
    this.onPause = onPause;
    this.onNext = onNext;
    this.onPrevious = onPrevious;
    this.onStop = onStop;

    try {
      _smtc = SMTCWindows(
        config: const SMTCConfig(
          fastForwardEnabled: false,
          rewindEnabled: false,
          prevEnabled: true,
          nextEnabled: true,
          pauseEnabled: true,
          playEnabled: true,
          stopEnabled: true,
        ),
        metadata: const MusicMetadata(
          title: 'Anywhere Music Player',
          artist: '',
          album: '',
          thumbnail: '',
        ),
      );

      // Listen for button presses
      _smtc!.buttonPressStream.listen((event) {
        switch (event) {
          case PressedButton.play:
            onPlay?.call();
            break;
          case PressedButton.pause:
            onPause?.call();
            break;
          case PressedButton.next:
            onNext?.call();
            break;
          case PressedButton.previous:
            onPrevious?.call();
            break;
          case PressedButton.stop:
            onStop?.call();
            break;
          default:
            break;
        }
      });

      _isInitialized = true;
      debugPrint('✅ Windows Media Controls initialized');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize Windows Media Controls: $e');
    }
  }

  /// Update the metadata shown in taskbar
  Future<void> updateMetadata(Track track) async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    try {
      await _smtc!.updateMetadata(MusicMetadata(
        title: track.title,
        artist: track.folderPath,
        album: track.folderPath,
        thumbnail: track.coverArtUrl ?? '',
      ));
      debugPrint('📻 Updated SMTC metadata: ${track.title}');
    } catch (e) {
      debugPrint('⚠️ Failed to update SMTC metadata: $e');
    }
  }

  /// Update playback status
  Future<void> updatePlaybackStatus({required bool isPlaying}) async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    try {
      await _smtc!.setPlaybackStatus(
        isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to update SMTC playback status: $e');
    }
  }

  /// Enable/disable previous button based on playlist position
  Future<void> updateButtonStates({
    required bool canPrevious,
    required bool canNext,
  }) async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    try {
      await _smtc!.updateConfig(SMTCConfig(
        fastForwardEnabled: false,
        rewindEnabled: false,
        prevEnabled: canPrevious,
        nextEnabled: canNext,
        pauseEnabled: true,
        playEnabled: true,
        stopEnabled: true,
      ));
    } catch (e) {
      debugPrint('⚠️ Failed to update SMTC button states: $e');
    }
  }

  /// Clear metadata and disable controls
  Future<void> clear() async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    try {
      await _smtc!.clearMetadata();
      await _smtc!.setPlaybackStatus(PlaybackStatus.stopped);
    } catch (e) {
      debugPrint('⚠️ Failed to clear SMTC: $e');
    }
  }

  /// Dispose the service
  Future<void> dispose() async {
    if (_smtc != null) {
      await _smtc!.dispose();
      _smtc = null;
    }
    _isInitialized = false;
  }
}
