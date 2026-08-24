import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'mpris_service.dart';
import 'now_playing_presence.dart';
import 'stream_url_resolver.dart';

/// Linux presence: MPRIS (org.mpris.MediaPlayer2), so hardware media keys
/// and desktop-shell media widgets can control playback — see
/// [MprisMediaService] for why this is a hand-rolled D-Bus service rather
/// than a package.
class LinuxPresence implements NowPlayingPresence {
  LinuxPresence({
    required StreamUrlResolver resolver,
    MprisMediaService? mediaService,
  }) : _resolver = resolver,
       _mediaService = mediaService ?? MprisMediaService.instance;

  final StreamUrlResolver _resolver;
  final MprisMediaService _mediaService;

  AudioPlayer? _player;
  PlaybackCommands? _commands;
  bool _mprisReady = false;

  @override
  void bind(AudioPlayer player, PlaybackCommands commands) {
    _player = player;
    _commands = commands;
  }

  /// MPRIS init is deliberately lazy — deferred to the first [show] rather
  /// than [bind] — so it only ever happens if something actually plays, same
  /// as WindowsPresence's SMTC init.
  Future<void> _ensureMprisInitialized() async {
    if (_mprisReady) return;
    _mprisReady = true;
    final commands = _commands;
    try {
      await _mediaService.initialize(
        onPlay: commands?.play,
        onPause: commands?.pause,
        onNext: commands?.next,
        onPrevious: commands?.previous,
        onStop: commands?.stop,
        positionProvider: () => _player?.position ?? Duration.zero,
      );
    } catch (e) {
      debugPrint('Failed to initialize MPRIS: $e');
    }
  }

  @override
  void show(Track track) {
    final artUrl = _resolver.resolveCoverUrl(track);
    if (_mprisReady) {
      _mediaService.updateMetadata(track, artUrl: artUrl);
    } else {
      unawaited(_ensureMprisInitialized().then((_) {
        _mediaService.updateMetadata(track, artUrl: artUrl);
        _mediaService.updatePlaybackStatus(isPlaying: _player?.playing ?? false);
      }));
    }
  }

  @override
  void setPlaying(bool playing) {
    _mediaService.updatePlaybackStatus(isPlaying: playing);
  }

  @override
  void clear() {
    _mediaService.clear();
  }

  @override
  void dispose() {
    _mediaService.dispose();
  }
}
