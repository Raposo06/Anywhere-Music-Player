import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import '../models/track.dart';

/// Service to handle Windows System Media Transport Controls.
/// This enables taskbar thumbnail controls (play/pause, next, prev)
/// and keyboard media key support.
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

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Initialize the Windows media controls.
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
        },
        cancelOnError: false,
      );

      _isInitialized = true;
      _initializeTaskbarButtons();
    } catch (e) {
      debugPrint('Failed to initialize Windows Media Controls: $e');
    }
  }

  /// Initialize taskbar thumbnail toolbar buttons (prev, play/pause, next).
  Future<void> _initializeTaskbarButtons() async {
    if (_taskbarButtonsInitialized) return;

    try {
      final iconsExist = await _checkIconsExist();
      if (!iconsExist) return;

      _taskbarButtonsInitialized = true;
      await _updateTaskbarButtons();
    } catch (e) {
      debugPrint('Failed to initialize taskbar buttons: $e');
      _taskbarButtonsInitialized = false;
    }
  }

  Future<bool> _checkIconsExist() async {
    try {
      await rootBundle.load('assets/icons/play.ico');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update taskbar buttons with current play state.
  Future<void> _updateTaskbarButtons() async {
    if (!isSupported || !_taskbarButtonsInitialized) return;

    try {
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/prev.ico'),
          'Previous',
          () => onPrevious?.call(),
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            _isPlaying ? 'assets/icons/pause.ico' : 'assets/icons/play.ico',
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
      debugPrint('Failed to update taskbar buttons: $e');
    }
  }

  /// Update the metadata shown in Windows media overlay.
  Future<void> updateMetadata(Track track) async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    try {
      final title = track.title.isNotEmpty ? track.title : 'Unknown Track';
      final artist =
          track.folderPath.isNotEmpty ? track.folderPath : 'Unknown Artist';
      final thumbnail = track.coverArtUrl;

      await _smtc!.updateMetadata(MusicMetadata(
        title: title,
        artist: artist,
        album: artist,
        thumbnail: (thumbnail != null && thumbnail.isNotEmpty) ? thumbnail : null,
      ));
    } catch (e) {
      debugPrint('Failed to update SMTC metadata: $e');
    }
  }

  /// Update playback status (play/pause state).
  void updatePlaybackStatus({required bool isPlaying}) {
    if (!isSupported || !_isInitialized) return;

    final bool changed = _isPlaying != isPlaying;
    _isPlaying = isPlaying;

    if (_smtc != null) {
      try {
        _smtc!.setPlaybackStatus(
          isPlaying ? PlaybackStatus.Playing : PlaybackStatus.Paused,
        );
      } catch (e) {
        debugPrint('Failed to update SMTC playback status: $e');
      }
    }

    if (_taskbarButtonsInitialized && changed) {
      _updateTaskbarButtons();
    }
  }

  /// Clear metadata and disable controls.
  Future<void> clear() async {
    if (!isSupported || !_isInitialized || _smtc == null) return;

    try {
      await _smtc!.clearMetadata();
      await _smtc!.setPlaybackStatus(PlaybackStatus.Stopped);
    } catch (e) {
      debugPrint('Failed to clear SMTC: $e');
    }
  }

  /// Dispose the service.
  Future<void> dispose() async {
    await _buttonPressSubscription?.cancel();
    _buttonPressSubscription = null;

    if (_smtc != null) {
      try {
        await _smtc!.dispose();
      } catch (_) {}
      _smtc = null;
    }
    _isInitialized = false;
    _taskbarButtonsInitialized = false;
  }
}
