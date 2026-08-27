import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:window_manager/window_manager.dart';
import '../models/track.dart';
import 'now_playing_presence.dart';
import 'stream_url_resolver.dart';
import 'windows_media_controls_service.dart';
import 'windows_wakelock.dart';

/// Windows presence: SMTC (System Media Transport Controls) + taskbar
/// thumbnail buttons + window title + a wakelock while playing. See
/// docs/decisions.md for why the wakelock omits ES_DISPLAY_REQUIRED (the
/// screen can still sleep; only system suspend is blocked).
class WindowsPresence implements NowPlayingPresence {
  WindowsPresence({
    required StreamUrlResolver resolver,
    WindowsMediaControlsService? mediaControls,
  }) : _resolver = resolver,
       _mediaControls = mediaControls ?? WindowsMediaControlsService.instance;

  final StreamUrlResolver _resolver;
  final WindowsMediaControlsService _mediaControls;
  static const _appName = 'Anywhere Music Player';

  AudioPlayer? _player;
  PlaybackCommands? _commands;
  bool _smtcReady = false;
  StreamSubscription<bool>? _playingSubscription;

  @override
  void bind(AudioPlayer player, PlaybackCommands commands) {
    // Only kept to read .playing when SMTC init resolves, below — SMTC talks
    // through the callbacks, not the player, for everything else.
    _player = player;
    _commands = commands;

    // Subscribed directly to the player's raw stream, not routed through
    // [setPlaying]: that call is gated on "a track is current" (it exists to
    // feed SMTC, which needs metadata to show), but the wakelock must track
    // literal play/pause state regardless — the PC should never suspend
    // while audio is actually playing. Was unconditional before the
    // NowPlayingPresence seam folded wakelock and SMTC into one call; see
    // docs/decisions.md.
    _playingSubscription = player.playingStream.listen((playing) {
      if (playing) {
        WindowsWakelock.enable();
      } else {
        WindowsWakelock.disable();
      }
    });
  }

  /// SMTC init is deliberately lazy — deferred to the first [show] rather
  /// than [bind] — so it only ever happens if something actually plays.
  Future<void> _ensureSmtcInitialized() async {
    if (_smtcReady) return;
    _smtcReady = true;
    final commands = _commands;
    try {
      await _mediaControls.initialize(
        onPlay: commands?.play,
        onPause: commands?.pause,
        onNext: commands?.next,
        onPrevious: commands?.previous,
        onStop: commands?.stop,
      );
    } catch (e) {
      debugPrint('Failed to initialize Windows media controls: $e');
    }
  }

  @override
  void show(Track track) {
    windowManager.setTitle('${track.title} - $_appName');
    final thumbnail = _resolver.resolveCoverUrl(track);
    if (_smtcReady) {
      _mediaControls.updateMetadata(track, thumbnail: thumbnail);
    } else {
      unawaited(_ensureSmtcInitialized().then((_) {
        _mediaControls.updateMetadata(track, thumbnail: thumbnail);
        _mediaControls.updatePlaybackStatus(isPlaying: _player?.playing ?? false);
      }));
    }
  }

  @override
  void setPlaying(bool playing) {
    _mediaControls.updatePlaybackStatus(isPlaying: playing);
  }

  @override
  void clear() {
    windowManager.setTitle(_appName);
    _mediaControls.clear();
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    WindowsWakelock.disable();
    _mediaControls.dispose();
  }
}
