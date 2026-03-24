import 'dart:async';
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
    if (!isSupported) return;

    if (_isInitialized) return;

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
        ),
      );

      _buttonPressSubscription = _smtc!.buttonPressStream.listen(
        (event) {
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
        },
        onError: (error) {
          debugPrint('SMTC button stream error: $error');
          _handleStreamError();
        },
        cancelOnError: false,
      );

      _isInitialized = true;
      await _initializeTaskbarButtons();
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
        return;
      }

      await _updateTaskbarButtons();
      _taskbarButtonsInitialized = true;
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
      // Set taskbar buttons with actual callbacks
      // Note: Taskbar button clicks are separate from keyboard events (SMTC buttonPressStream)
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/prev.ico'),
          'Previous',
          () => onPrevious?.call(),
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            _isPlaying ? 'assets/icons/pause.ico' : 'assets/icons/play.ico'
          ),
          _isPlaying ? 'Pause' : 'Play',
          () {
            if (_isPlaying) {
              onPause?.call();
            } else {
              onPlay?.call();
            }
          },
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/next.ico'),
          'Next',
          () => onNext?.call(),
        ),
      ]);
    } catch (e) {
      debugPrint('⚠️ Failed to update taskbar buttons: $e');
    }
  }

  /// Update the metadata shown in Windows media overlay / taskbar
  Future<void> updateMetadata(Track track) async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    try {
      final title = track.title.isNotEmpty ? track.title : 'Unknown Track';
      final artist = track.folderPath.isNotEmpty ? track.folderPath : 'Unknown Artist';
      final thumbnail = track.coverArtUrl;

      if (thumbnail != null && thumbnail.isNotEmpty) {
        await _smtc!.updateMetadata(MusicMetadata(
          title: title,
          artist: artist,
          album: artist,
          thumbnail: thumbnail,
        ));
      } else {
        await _smtc!.updateMetadata(MusicMetadata(
          title: title,
          artist: artist,
          album: artist,
        ));
      }
    } catch (e) {
      debugPrint('Failed to update SMTC metadata: $e');
    }
  }

  /// Update playback status
  Future<void> updatePlaybackStatus({required bool isPlaying}) async {
    if (!isSupported) return;

    final bool playStateChanged = _isPlaying != isPlaying;
    _isPlaying = isPlaying;

    if (_taskbarButtonsInitialized && playStateChanged) {
      await _updateTaskbarButtons();
    }
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
