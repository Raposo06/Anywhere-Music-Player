import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import '../models/track.dart';

/// Service to handle Windows System Media Transport Controls
/// This enables taskbar thumbnail controls (play/pause, next, prev)
class WindowsMediaControlsService {
  static WindowsMediaControlsService? _instance;
  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _buttonPressSubscription;
  bool _isInitialized = false;
  bool _taskbarButtonsInitialized = false;
  bool _isPlaying = false;

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
    if (!isSupported) {
      debugPrint('⚠️ Windows Media Controls not supported on this platform');
      return;
    }

    if (_isInitialized) {
      debugPrint('⚠️ Windows Media Controls already initialized');
      return;
    }

    debugPrint('🎹 Initializing Windows Media Controls...');
    this.onPlay = onPlay;
    this.onPause = onPause;
    this.onNext = onNext;
    this.onPrevious = onPrevious;
    this.onStop = onStop;

    debugPrint('🎹 Callbacks registered:');
    debugPrint('   Play: ${this.onPlay != null}');
    debugPrint('   Pause: ${this.onPause != null}');
    debugPrint('   Next: ${this.onNext != null}');
    debugPrint('   Previous: ${this.onPrevious != null}');
    debugPrint('   Stop: ${this.onStop != null}');

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
          artist: 'Unknown Artist',
          album: 'Unknown Album',
        ),
      );

      // Listen for button presses with error handling
      // Using instance variables (this.onPlay, etc.) instead of parameters to ensure
      // callbacks are always current and not stale closures
      _buttonPressSubscription = _smtc!.buttonPressStream.listen(
        (event) {
          debugPrint('🎹 Windows keyboard button pressed: $event');
          switch (event) {
            case PressedButton.play:
              debugPrint('▶️ Play button pressed (callback: ${this.onPlay != null ? "available" : "NULL"})');
              if (this.onPlay != null) {
                this.onPlay!();
              } else {
                debugPrint('⚠️ Play callback is null!');
              }
              break;
            case PressedButton.pause:
              debugPrint('⏸️ Pause button pressed (callback: ${this.onPause != null ? "available" : "NULL"})');
              if (this.onPause != null) {
                this.onPause!();
              } else {
                debugPrint('⚠️ Pause callback is null!');
              }
              break;
            case PressedButton.next:
              debugPrint('⏭️ Next button pressed (callback: ${this.onNext != null ? "available" : "NULL"})');
              if (this.onNext != null) {
                this.onNext!();
              } else {
                debugPrint('⚠️ Next callback is null!');
              }
              break;
            case PressedButton.previous:
              debugPrint('⏮️ Previous button pressed (callback: ${this.onPrevious != null ? "available" : "NULL"})');
              if (this.onPrevious != null) {
                this.onPrevious!();
              } else {
                debugPrint('⚠️ Previous callback is null!');
              }
              break;
            case PressedButton.stop:
              debugPrint('⏹️ Stop button pressed (callback: ${this.onStop != null ? "available" : "NULL"})');
              if (this.onStop != null) {
                this.onStop!();
              } else {
                debugPrint('⚠️ Stop callback is null!');
              }
              break;
            default:
              debugPrint('⚠️ Unknown button pressed: $event');
              break;
          }
        },
        onError: (error) {
          debugPrint('🔴 Error in button press stream: $error');
          // Try to reinitialize if the stream fails
          _handleStreamError();
        },
        cancelOnError: false, // Keep listening even if there's an error
      );

      _isInitialized = true;
      debugPrint('✅ Windows Media Controls initialized');

      // Initialize taskbar thumbnail buttons
      await _initializeTaskbarButtons();

      debugPrint('✅ SMTC ready for keyboard input');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize Windows Media Controls: $e');
    }
  }

  /// Initialize taskbar thumbnail toolbar buttons (prev, play/pause, next)
  Future<void> _initializeTaskbarButtons() async {
    if (_taskbarButtonsInitialized) return;

    try {
      // Check if icon files exist
      final iconsExist = await _checkIconsExist();
      if (!iconsExist) {
        debugPrint('⚠️ Taskbar icons not found. Skipping thumbnail buttons.');
        debugPrint('   Add prev.ico, play.ico, pause.ico, next.ico to assets/icons/');
        return;
      }

      await _updateTaskbarButtons();
      _taskbarButtonsInitialized = true;
      debugPrint('✅ Taskbar thumbnail buttons initialized');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize taskbar buttons: $e');
    }
  }

  /// Check if required icon files exist
  Future<bool> _checkIconsExist() async {
    try {
      // Try to load one of the icons to verify assets are available
      await rootBundle.load('assets/icons/play.ico');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update taskbar buttons with current play state
  Future<void> _updateTaskbarButtons() async {
    if (!isSupported) return;

    try {
      // Set taskbar buttons with empty callbacks to prevent interference with keyboard events
      // All media control events will be routed through SMTC buttonPressStream instead
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/prev.ico'),
          'Previous',
          () {}, // Empty callback - let SMTC handle it
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            _isPlaying ? 'assets/icons/pause.ico' : 'assets/icons/play.ico'
          ),
          _isPlaying ? 'Pause' : 'Play',
          () {}, // Empty callback - let SMTC handle it
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/next.ico'),
          'Next',
          () {}, // Empty callback - let SMTC handle it
        ),
      ]);
    } catch (e) {
      debugPrint('⚠️ Failed to update taskbar buttons: $e');
    }
  }

  /// Update the metadata shown in taskbar
  Future<void> updateMetadata(Track track) async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    // DISABLED: updateMetadata() also disrupts keyboard controls
    // Calling _smtc!.updateMetadata() appears to reset/interfere with buttonPressStream
    // Static metadata from initialization is acceptable for consistent keyboard controls
    debugPrint('⚠️ updateMetadata called but disabled to prevent keyboard interference: ${track.title}');
    return;

    // try {
    //   // smtc_windows crashes with empty strings, so provide defaults
    //   final title = track.title.isNotEmpty ? track.title : 'Unknown Track';
    //   final artist = track.folderPath.isNotEmpty ? track.folderPath : 'Unknown Artist';
    //   final thumbnail = track.coverArtUrl;

    //   // Only include thumbnail if it's a valid non-empty URL
    //   if (thumbnail != null && thumbnail.isNotEmpty) {
    //     await _smtc!.updateMetadata(MusicMetadata(
    //       title: title,
    //       artist: artist,
    //       album: artist,
    //       thumbnail: thumbnail,
    //     ));
    //   } else {
    //     await _smtc!.updateMetadata(MusicMetadata(
    //       title: title,
    //       artist: artist,
    //       album: artist,
    //     ));
    //   }
    //   debugPrint('📻 Updated SMTC metadata: $title');
    // } catch (e) {
    //   debugPrint('⚠️ Failed to update SMTC metadata: $e');
    // }
  }

  /// Update playback status
  Future<void> updatePlaybackStatus({required bool isPlaying}) async {
    if (!isSupported) return;

    final bool playStateChanged = _isPlaying != isPlaying;
    _isPlaying = isPlaying;

    debugPrint('🎵 SMTC playback status: ${isPlaying ? "Playing" : "Paused"} (state changed: $playStateChanged)');

    // Update SMTC
    if (_isInitialized && _smtc != null) {
      try {
        await _smtc!.setPlaybackStatus(
          isPlaying ? PlaybackStatus.Playing : PlaybackStatus.Paused,
        );
      } catch (e) {
        debugPrint('⚠️ Failed to update SMTC playback status: $e');
      }
    }

    // DISABLED: updateTaskbarButtons also disrupts keyboard controls
    // WindowsTaskbar.setThumbnailToolbar() appears to interfere with SMTC keyboard routing
    // Taskbar buttons will show the initial state only (acceptable trade-off)
    // if (_taskbarButtonsInitialized && playStateChanged) {
    //   await _updateTaskbarButtons();
    // }
  }

  /// Enable/disable previous button based on playlist position
  Future<void> updateButtonStates({
    required bool canPrevious,
    required bool canNext,
  }) async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    // DISABLED: updateConfig() disrupts the buttonPressStream keyboard event routing
    // Calling updateConfig seems to reset or interfere with the keyboard event listener
    // Keeping all buttons enabled at all times is acceptable for consistent keyboard controls
    debugPrint('⚠️ updateButtonStates called but disabled to prevent keyboard interference (canPrev: $canPrevious, canNext: $canNext)');

    // try {
    //   await _smtc!.updateConfig(SMTCConfig(
    //     fastForwardEnabled: false,
    //     rewindEnabled: false,
    //     prevEnabled: canPrevious,
    //     nextEnabled: canNext,
    //     pauseEnabled: true,
    //     playEnabled: true,
    //     stopEnabled: true,
    //   ));
    // } catch (e) {
    //   debugPrint('⚠️ Failed to update SMTC button states: $e');
    // }
  }

  /// Clear metadata and disable controls
  Future<void> clear() async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    try {
      await _smtc!.clearMetadata();
      await _smtc!.setPlaybackStatus(PlaybackStatus.Stopped);
    } catch (e) {
      debugPrint('⚠️ Failed to clear SMTC: $e');
    }
  }

  /// Handle stream errors by attempting to recover
  Future<void> _handleStreamError() async {
    debugPrint('🔄 Attempting to recover from button press stream error...');

    // Cancel existing subscription
    await _buttonPressSubscription?.cancel();
    _buttonPressSubscription = null;

    // Mark as not initialized to allow re-initialization
    _isInitialized = false;

    // Try to reinitialize after a short delay
    await Future.delayed(const Duration(milliseconds: 500));

    await initialize(
      onPlay: onPlay,
      onPause: onPause,
      onNext: onNext,
      onPrevious: onPrevious,
      onStop: onStop,
    );
  }

  /// Dispose the service
  Future<void> dispose() async {
    await _buttonPressSubscription?.cancel();
    _buttonPressSubscription = null;

    if (_smtc != null) {
      await _smtc!.dispose();
      _smtc = null;
    }
    _isInitialized = false;
    _taskbarButtonsInitialized = false;
  }
}
