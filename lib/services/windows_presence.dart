import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import '../models/track.dart';
import 'now_playing_presence.dart';
import 'stream_url_resolver.dart';
import 'windows_wakelock.dart';

/// Windows presence: SMTC (System Media Transport Controls, which is also
/// what the keyboard media keys drive) + taskbar thumbnail buttons + window
/// title + a wakelock while playing. See docs/decisions.md for why the
/// wakelock omits ES_DISPLAY_REQUIRED (the screen can still sleep; only
/// system suspend is blocked).
///
/// Construct only on Windows — `main()` picks the adapter by platform. Every
/// OS call is best-effort: SMTC or the taskbar failing must never take
/// playback down with it.
class WindowsPresence implements NowPlayingPresence {
  WindowsPresence({required StreamUrlResolver resolver}) : _resolver = resolver;

  final StreamUrlResolver _resolver;
  static const _appName = 'Anywhere Music Player';

  PlaybackCommands? _commands;
  StreamSubscription<bool>? _playingSubscription;
  bool _playing = false;

  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _buttonPressSubscription;
  // Set at the first show(); once set, an init is in flight or done.
  Future<void>? _smtcInit;
  bool _taskbarButtonsReady = false;

  @override
  void bind(PlaybackCommands commands, PlaybackSignals signals) {
    _commands = commands;

    // The raw stream, not [setPlaying]: that call is gated on "a track is
    // current" (it exists to feed SMTC, which needs metadata to show), but
    // the wakelock must track literal play/pause state regardless — the PC
    // should never suspend while audio is actually playing. Was unconditional
    // before the NowPlayingPresence seam folded wakelock and SMTC into one
    // call; see docs/decisions.md.
    _playingSubscription = signals.playing.listen((playing) {
      _playing = playing;
      if (playing) {
        WindowsWakelock.enable();
      } else {
        WindowsWakelock.disable();
      }
    });
  }

  @override
  void show(Track track) {
    windowManager.setTitle('${track.title} - $_appName');
    final thumbnail = _resolver.resolveCoverUrl(track);
    // SMTC init is deliberately lazy — the first show(), not bind() — so it
    // only ever happens if something actually plays. Chained rather than
    // awaited: show() is synchronous on the seam, and a second show() during
    // init queues its metadata behind the same future rather than starting
    // another init.
    _smtcInit ??= _initSmtc();
    unawaited(
      _smtcInit!.then((_) {
        _updateMetadata(track, thumbnail: thumbnail);
        _updatePlaybackStatus(_playing);
      }),
    );
  }

  @override
  void setPlaying(bool playing) => _updatePlaybackStatus(playing);

  @override
  void clear() {
    windowManager.setTitle(_appName);
    final smtc = _smtc;
    if (smtc == null) return;
    unawaited(
      smtc
          .clearMetadata()
          .then((_) => smtc.setPlaybackStatus(PlaybackStatus.Stopped))
          .catchError((Object e) => debugPrint('Failed to clear SMTC: $e')),
    );
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    WindowsWakelock.disable();
    _buttonPressSubscription?.cancel();
    _buttonPressSubscription = null;
    final smtc = _smtc;
    _smtc = null;
    if (smtc != null) {
      unawaited(smtc.dispose().catchError((Object _) {}));
    }
    _taskbarButtonsReady = false;
  }

  // -------- SMTC --------

  Future<void> _initSmtc() async {
    try {
      final smtc = SMTCWindows(
        config: const SMTCConfig(
          fastForwardEnabled: false,
          rewindEnabled: false,
          prevEnabled: true,
          nextEnabled: true,
          pauseEnabled: true,
          playEnabled: true,
          stopEnabled: true,
        ),
        metadata: const MusicMetadata(title: _appName, artist: '', album: ''),
      );
      _buttonPressSubscription = smtc.buttonPressStream.listen(
        (event) {
          final commands = _commands;
          if (commands == null) return;
          switch (event) {
            case PressedButton.play:
              commands.play();
            case PressedButton.pause:
              commands.pause();
            case PressedButton.next:
              commands.next();
            case PressedButton.previous:
              commands.previous();
            case PressedButton.stop:
              commands.stop();
            default:
              break;
          }
        },
        onError: (Object e) => debugPrint('SMTC button stream error: $e'),
        cancelOnError: false,
      );
      _smtc = smtc;
      await _initTaskbarButtons();
    } catch (e) {
      debugPrint('Failed to initialize Windows media controls: $e');
    }
  }

  void _updateMetadata(Track track, {String? thumbnail}) {
    final smtc = _smtc;
    if (smtc == null) return;
    final title = track.title.isNotEmpty ? track.title : 'Unknown Track';
    final artist = track.folderPath.isNotEmpty
        ? track.folderPath
        : 'Unknown Artist';
    unawaited(
      smtc
          .updateMetadata(
            MusicMetadata(
              title: title,
              artist: artist,
              album: artist,
              thumbnail: (thumbnail != null && thumbnail.isNotEmpty)
                  ? thumbnail
                  : null,
            ),
          )
          .catchError(
            (Object e) => debugPrint('Failed to update SMTC metadata: $e'),
          ),
    );
  }

  void _updatePlaybackStatus(bool playing) {
    final smtc = _smtc;
    if (smtc == null) return;
    _playing = playing;
    try {
      smtc.setPlaybackStatus(
        playing ? PlaybackStatus.Playing : PlaybackStatus.Paused,
      );
    } catch (e) {
      debugPrint('Failed to update SMTC playback status: $e');
    }
    // Redrawn on every report, not only on a change: the raw stream in
    // bind() has usually set [_playing] already by the time the gated
    // report arrives, so "did it change?" would answer no and the toolbar
    // would keep the stale icon. Reports only arrive on transitions anyway.
    if (_taskbarButtonsReady) unawaited(_updateTaskbarButtons());
  }

  // -------- Taskbar thumbnail toolbar (prev, play/pause, next) --------

  Future<void> _initTaskbarButtons() async {
    try {
      // The icons are optional assets; without them there is no toolbar.
      await rootBundle.load('assets/icons/play.ico');
    } catch (_) {
      return;
    }
    _taskbarButtonsReady = true;
    await _updateTaskbarButtons();
  }

  Future<void> _updateTaskbarButtons() async {
    final commands = _commands;
    if (!_taskbarButtonsReady || commands == null) return;
    try {
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/prev.ico'),
          'Previous',
          commands.previous,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            _playing ? 'assets/icons/pause.ico' : 'assets/icons/play.ico',
          ),
          _playing ? 'Pause' : 'Play',
          _playing ? commands.pause : commands.play,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/next.ico'),
          'Next',
          commands.next,
        ),
      ]);
    } catch (e) {
      debugPrint('Failed to update taskbar buttons: $e');
    }
  }
}
