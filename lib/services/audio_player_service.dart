import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:window_manager/window_manager.dart';
import '../models/track.dart';
import 'audio_handler.dart';
import 'windows_media_controls_service.dart';
import 'windows_wakelock.dart';

enum RepeatMode { off, all, one }

/// Plays one track at a time. All sequencing (playlist order, shuffle, loop,
/// queue) is handled in Dart so we don't depend on just_audio's
/// ConcatenatingAudioSource — which is buggy on just_audio_media_kit
/// (Windows/Linux). The user-facing API is unchanged.
class AudioPlayerService with ChangeNotifier {
  AudioPlayer? _player;
  final MusicAudioHandler? _audioHandler;
  final WindowsMediaControlsService _windowsMediaControls =
      WindowsMediaControlsService.instance;

  // Active playlist (the folder/album the user is browsing).
  List<Track> _playlist = [];
  // Position in _playlist that will be resumed when the queue empties.
  int _currentIndex = -1;
  // Explicit FIFO queue. Independent of shuffle.
  final List<Track> _queue = [];
  // The track currently coming out of the speakers — may be a _playlist item
  // or a queue item.
  Track? _currentTrack;
  // True iff _currentTrack came from _queue (so _currentIndex points at the
  // playlist track we'll return to once the queue is done).
  bool _playingFromQueue = false;

  // Shuffle plumbing: a permutation of playlist indices and where we are in it.
  List<int> _shuffleOrder = [];
  int _shufflePos = 0;
  bool _isShuffleEnabled = false;

  RepeatMode _repeatMode = RepeatMode.all;
  double _volume = 1.0;
  String? _lastError;
  bool _isLoading = false;
  int _loadToken = 0;

  // Mid-stream drop recovery: bounded auto-resume of the current track when the
  // network/server closes a connection mid-playback.
  int _resumeAttempts = 0;
  String? _resumeTrackId;
  DateTime? _lastResumeAt;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  bool _playerInitialized = false;

  // Provide safe stream getters that return empty streams before init.
  static final _emptyDurationStream = Stream<Duration>.empty();
  static final _emptyNullDurationStream = Stream<Duration?>.empty();
  static final _emptyBoolStream = Stream<bool>.empty();

  Stream<Duration> get positionStream =>
      _player?.positionStream ?? _emptyDurationStream;
  Stream<Duration?> get durationStream =>
      _player?.durationStream ?? _emptyNullDurationStream;
  Stream<Duration> get bufferedPositionStream =>
      _player?.bufferedPositionStream ?? _emptyDurationStream;
  Stream<bool> get playingStream => _player?.playingStream ?? _emptyBoolStream;

  AudioPlayer? get player => _player;
  Track? get currentTrack => _currentTrack;
  List<Track> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  List<Track> get queue => List.unmodifiable(_queue);
  int get queueLength => _queue.length;

  /// The upcoming tracks from the browsing context (playlist), in play order
  /// and shuffle-aware, starting after the current playback position. Does not
  /// wrap around on repeat-all. Independent of the manual [queue].
  List<Track> get upcomingFromContext {
    if (_playlist.isEmpty) return const [];
    final result = <Track>[];
    if (_isShuffleEnabled && _shuffleOrder.length == _playlist.length) {
      for (var p = _shufflePos + 1; p < _shuffleOrder.length; p++) {
        result.add(_playlist[_shuffleOrder[p]]);
      }
    } else {
      for (var i = _currentIndex + 1; i < _playlist.length; i++) {
        result.add(_playlist[i]);
      }
    }
    return List.unmodifiable(result);
  }
  bool get isLoading => _isLoading;
  bool get isShuffleEnabled => _isShuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  double get volume => _volume;
  String? get lastError => _lastError;

  bool get isPlaying => _player?.playing ?? false;
  Duration? get duration => _player?.duration;
  Duration? get position => _player?.position;
  Duration? get bufferedPosition => _player?.bufferedPosition;

  bool get _isWindows => !kIsWeb && Platform.isWindows;

  static const _appName = 'Anywhere Music Player';

  bool _windowsMediaControlsReady = false;

  void _updateWindowsMetadata(Track? track) {
    if (!_isWindows) return;
    if (track != null) {
      windowManager.setTitle('${track.title} - $_appName');
      if (!_windowsMediaControlsReady) {
        _windowsMediaControlsReady = true;
        _initializeWindowsMediaControls().then((_) {
          _windowsMediaControls.updateMetadata(track);
          _windowsMediaControls.updatePlaybackStatus(
            isPlaying: _player?.playing ?? false,
          );
        });
      } else {
        _windowsMediaControls.updateMetadata(track);
      }
    } else {
      windowManager.setTitle(_appName);
    }
  }

  AudioPlayerService({MusicAudioHandler? audioHandler})
    : _audioHandler = audioHandler;

  /// Lazily initialize the AudioPlayer and stream listeners.
  void _ensurePlayerInitialized() {
    if (_playerInitialized) return;
    _playerInitialized = true;

    _player = AudioPlayer();
    // We sequence manually, so always let the player report completion.
    _player!.setLoopMode(LoopMode.off);

    if (_audioHandler != null) {
      _audioHandler!.attachPlayer(
        player: _player!,
        onNextCallback: playNext,
        onPreviousCallback: playPrevious,
      );
    }

    _playingSubscription = _player!.playingStream.listen((playing) {
      if (_isWindows) {
        // Keep the PC awake while playing; release it when paused/stopped.
        if (playing) {
          WindowsWakelock.enable();
        } else {
          WindowsWakelock.disable();
        }
        if (_currentTrack != null) {
          _windowsMediaControls.updatePlaybackStatus(isPlaying: playing);
        }
      }
      notifyListeners();
    });

    // When the single-track source finishes, decide what to play next.
    _playerStateSubscription = _player!.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && !_isLoading) {
        _onTrackCompleted();
      }
    });

    _playbackEventSubscription = _player!.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) => _handleStreamError(e),
    );
  }

  Future<void> _initializeWindowsMediaControls() async {
    if (!_isWindows) return;
    try {
      await _windowsMediaControls.initialize(
        onPlay: () => _player?.play(),
        onPause: () => _player?.pause(),
        onNext: () => playNext(),
        onPrevious: () => playPrevious(),
        onStop: () => stop(),
      );
    } catch (e) {
      debugPrint('Failed to initialize Windows media controls: $e');
    }
  }

  void _handlePlaybackError(Object error) {
    _lastError = 'Playback error: $error';
    debugPrint('Playback error: $error');
    notifyListeners();
  }

  /// Recover from a mid-playback stream drop (e.g. the server/proxy closed a
  /// long-lived connection): re-open the current track and seek back to where
  /// it stopped, then resume. Only acts on steady-state playback — not during a
  /// deliberate load, and not while paused (an idle connection often drops when
  /// paused; we must not auto-start it). Bounded to 3 *rapid* attempts; the
  /// counter resets after 30s of successful playback so a long track that drops
  /// occasionally keeps recovering, while a dead source won't loop forever.
  Future<void> _handleStreamError(Object error) async {
    final track = _currentTrack;
    final wasPlaying = _player?.playing ?? false;
    if (track == null || _isLoading || !wasPlaying) {
      _handlePlaybackError(error);
      return;
    }

    final now = DateTime.now();
    if (_resumeTrackId != track.id ||
        (_lastResumeAt != null &&
            now.difference(_lastResumeAt!) > const Duration(seconds: 30))) {
      _resumeAttempts = 0;
    }
    if (_resumeAttempts >= 3) {
      _handlePlaybackError(error);
      return;
    }
    _resumeTrackId = track.id;
    _lastResumeAt = now;
    _resumeAttempts++;

    final resumeFrom = _player?.position ?? Duration.zero;
    debugPrint(
      'AudioPlayerService: stream dropped, resume attempt #$_resumeAttempts '
      'at ${resumeFrom.inSeconds}s trackId=${track.id}',
    );

    final token = ++_loadToken;
    _isLoading = true;
    notifyListeners();
    try {
      await _setSourceWithRetry(track);
      if (token != _loadToken) return;
      await _player!.setVolume(_volume * _replayGainFactor(track));
      if (resumeFrom > Duration.zero) await _player!.seek(resumeFrom);
      _player!.play();
    } catch (e) {
      if (token != _loadToken) return;
      _handlePlaybackError(e);
    } finally {
      if (token == _loadToken) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  // -------- Source helpers --------

  MediaItem _buildMediaItem(Track track) => MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artist ?? '',
    album: track.album ?? '',
    duration: track.durationSeconds != null
        ? Duration(seconds: track.durationSeconds!)
        : null,
    artUri: track.coverArtUrl != null ? Uri.parse(track.coverArtUrl!) : null,
  );

  AudioSource _buildSource(Track track) =>
      AudioSource.uri(Uri.parse(track.streamUrl), tag: _buildMediaItem(track));

  /// Load the source, retrying once if it stalls. A single setAudioSource on
  /// the streaming backend (media_kit on Windows / the Android backend) can
  /// occasionally hang and never complete, which wedges playback ("freezes and
  /// never plays" on Next). Re-issuing the load recovers it — the same thing a
  /// manual Next press does, but automatic and on the same track.
  Future<void> _setSourceWithRetry(Track track) async {
    const loadTimeout = Duration(seconds: 12);
    try {
      await _player!.setAudioSource(_buildSource(track)).timeout(loadTimeout);
    } on TimeoutException {
      debugPrint('AudioPlayerService: load stalled, retrying trackId=${track.id}');
      await _player!.setAudioSource(_buildSource(track)).timeout(loadTimeout);
    }
  }

  void _logStreamParams(Track track) {
    final uri = Uri.tryParse(track.streamUrl);
    final params = uri?.queryParameters ?? const <String, String>{};
    final platform = kIsWeb
        ? 'web'
        : Platform.isAndroid
        ? 'android'
        : Platform.operatingSystem;

    debugPrint(
      'AudioPlayerService: loading stream '
      'platform=$platform '
      'format=${params['format'] ?? '(none)'} '
      'maxBitRate=${params['maxBitRate'] ?? '(none)'} '
      'estimateContentLength=${params['estimateContentLength'] ?? '(none)'} '
      'trackId=${track.id}',
    );
  }

  /// Load [track] as the single audio source and start playback. Race-safe
  /// against rapid successive calls via [_loadToken].
  Future<void> _loadAndPlay(Track track) async {
    final token = ++_loadToken;
    _currentTrack = track;
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      _logStreamParams(track);
      await _setSourceWithRetry(track);
      if (token != _loadToken) return;
      await _player!.setVolume(_volume * _replayGainFactor(track));
      _player!.play();
      if (_audioHandler != null) _audioHandler!.updateTrackInfo(track);
      _updateWindowsMetadata(track);
    } catch (e) {
      if (token != _loadToken) return;
      _handlePlaybackError(e);
    } finally {
      if (token == _loadToken) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // -------- Shuffle helpers --------

  void _regenerateShuffleOrder({int anchorAt = -1}) {
    if (_playlist.isEmpty) {
      _shuffleOrder = [];
      _shufflePos = 0;
      return;
    }
    _shuffleOrder = List.generate(_playlist.length, (i) => i)..shuffle();
    if (anchorAt >= 0 && anchorAt < _playlist.length) {
      final pos = _shuffleOrder.indexOf(anchorAt);
      if (pos > 0) {
        _shuffleOrder.removeAt(pos);
        _shuffleOrder.insert(0, anchorAt);
      }
    }
    _shufflePos = 0;
  }

  /// Next playlist index respecting shuffle and loop. Returns null when
  /// playback should stop (end of playlist with loop off).
  int? _nextPlaylistIndex() {
    if (_playlist.isEmpty) return null;
    if (_isShuffleEnabled && _shuffleOrder.length == _playlist.length) {
      var next = _shufflePos + 1;
      if (next >= _shuffleOrder.length) {
        if (_repeatMode == RepeatMode.all) {
          _regenerateShuffleOrder(anchorAt: _currentIndex);
          next = 0;
        } else {
          return null;
        }
      }
      _shufflePos = next;
      return _shuffleOrder[next];
    }
    var next = _currentIndex + 1;
    if (next >= _playlist.length) {
      if (_repeatMode == RepeatMode.all) {
        next = 0;
      } else {
        return null;
      }
    }
    return next;
  }

  /// What [playNext] would play right now — without mutating shuffle state.
  /// Used by the player screen to precache the next track's cover art so the
  /// transition between tracks doesn't flash an empty/loading frame. Returns
  /// null when end-of-playlist (repeat off) would stop playback.
  Track? peekNextTrack() {
    if (_queue.isNotEmpty) return _queue.first;
    if (_playlist.isEmpty || _currentIndex < 0) return null;

    if (_isShuffleEnabled && _shuffleOrder.length == _playlist.length) {
      var next = _shufflePos + 1;
      if (next >= _shuffleOrder.length) {
        if (_repeatMode != RepeatMode.all) return null;
        next = 0;
      }
      return _playlist[_shuffleOrder[next]];
    }

    var next = _currentIndex + 1;
    if (next >= _playlist.length) {
      if (_repeatMode != RepeatMode.all) return null;
      next = 0;
    }
    return _playlist[next];
  }

  int? _prevPlaylistIndex() {
    if (_playlist.isEmpty) return null;
    if (_isShuffleEnabled && _shuffleOrder.length == _playlist.length) {
      var prev = _shufflePos - 1;
      if (prev < 0) {
        if (_repeatMode == RepeatMode.all) {
          prev = _shuffleOrder.length - 1;
        } else {
          return null;
        }
      }
      _shufflePos = prev;
      return _shuffleOrder[prev];
    }
    var prev = _currentIndex - 1;
    if (prev < 0) {
      if (_repeatMode == RepeatMode.all) {
        prev = _playlist.length - 1;
      } else {
        return null;
      }
    }
    return prev;
  }

  // -------- Playback entry points --------

  /// Play a single track. Replaces the playlist context but preserves the
  /// user-built queue — switching the current song should not discard songs
  /// the user has explicitly lined up to play next.
  Future<void> playTrack(Track track) async {
    _ensurePlayerInitialized();
    _playlist = [track];
    _currentIndex = 0;
    _playingFromQueue = false;
    if (_isShuffleEnabled) _regenerateShuffleOrder(anchorAt: 0);
    await _loadAndPlay(track);
  }

  /// Play a playlist. Pass [startIndex] = -1 to let shuffle pick the first
  /// track at random, or use a specific index otherwise. Preserves the
  /// user-built queue so switching songs doesn't discard queued tracks.
  Future<void> playPlaylist(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    if (startIndex != -1 && (startIndex < 0 || startIndex >= tracks.length)) {
      return;
    }

    _ensurePlayerInitialized();
    _playlist = List.from(tracks);
    _playingFromQueue = false;

    final int resolvedStart;
    if (startIndex >= 0) {
      resolvedStart = startIndex;
    } else if (_isShuffleEnabled && tracks.length > 1) {
      resolvedStart = Random().nextInt(tracks.length);
    } else {
      resolvedStart = 0;
    }
    _currentIndex = resolvedStart;

    if (_isShuffleEnabled) {
      _regenerateShuffleOrder(anchorAt: resolvedStart);
    }

    await _loadAndPlay(_playlist[resolvedStart]);
  }

  Future<void> _onTrackCompleted() async {
    if (_repeatMode == RepeatMode.one && _currentTrack != null) {
      await _loadAndPlay(_currentTrack!);
      return;
    }
    await playNext();
  }

  /// Pick the next track to play. Queue takes priority over playlist
  /// advancement, regardless of shuffle. Called for both natural end-of-track
  /// and explicit "next" button.
  Future<void> playNext() async {
    _ensurePlayerInitialized();

    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _playingFromQueue = true;
      await _loadAndPlay(next);
      return;
    }

    if (_playlist.isEmpty) {
      await stop();
      return;
    }

    final next = _nextPlaylistIndex();
    if (next == null) {
      await stop();
      return;
    }
    _currentIndex = next;
    _playingFromQueue = false;
    await _loadAndPlay(_playlist[_currentIndex]);
  }

  /// Previous from a queue item returns to the playlist track that was
  /// interrupted. Previous from a playlist track steps one back in the
  /// playlist (or shuffle order).
  Future<void> playPrevious() async {
    _ensurePlayerInitialized();

    if (_playingFromQueue &&
        _currentIndex >= 0 &&
        _currentIndex < _playlist.length) {
      _playingFromQueue = false;
      await _loadAndPlay(_playlist[_currentIndex]);
      return;
    }

    if (_playlist.isEmpty) return;

    final prev = _prevPlaylistIndex();
    if (prev == null) return;
    _currentIndex = prev;
    _playingFromQueue = false;
    await _loadAndPlay(_playlist[_currentIndex]);
  }

  Future<void> togglePlayPause() async {
    if (_player == null) return;
    if (_player!.playing) {
      await _player!.pause();
    } else {
      _player!.play();
    }
  }

  Future<void> stop() async {
    if (_player != null) await _player!.stop();
    _currentTrack = null;
    _playingFromQueue = false;
    _queue.clear();
    _updateWindowsMetadata(null);
    if (_isWindows) _windowsMediaControls.clear();
    notifyListeners();
  }

  /// Seek the currently-loaded track to [position]. No-op if nothing is
  /// loaded. Preserves the play/pause state — playback continues from the
  /// new position if it was playing, stays paused otherwise.
  Future<void> seek(Duration position) async {
    if (_player == null || _currentTrack == null) return;
    try {
      await _player!.seek(position);
    } catch (e) {
      _handlePlaybackError(e);
    }
  }

  // -------- Queue API --------

  /// Append [track] to the end of the queue. No source mutation, no audio
  /// interruption. If nothing is playing, just starts [track].
  Future<void> addToQueue(Track track) async {
    if (_currentTrack == null) {
      await playTrack(track);
      return;
    }
    _queue.add(track);
    notifyListeners();
  }

  Future<void> removeFromQueue(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queue.length) return;
    _queue.removeAt(queueIndex);
    notifyListeners();
  }

  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    final t = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, t);
    notifyListeners();
  }

  /// Play the manual-queue track at [queueIndex] now, discarding the queued
  /// tracks ahead of it (the ones that would have played first).
  Future<void> jumpToQueued(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queue.length) return;
    _ensurePlayerInitialized();
    final track = _queue[queueIndex];
    _queue.removeRange(0, queueIndex + 1);
    _playingFromQueue = true;
    await _loadAndPlay(track);
  }

  /// Jump forward to the [autoIndex]-th track of [upcomingFromContext]. The
  /// cursor simply moves; skipped tracks are not removed and remain reachable
  /// via Previous.
  Future<void> jumpToUpcoming(int autoIndex) async {
    if (autoIndex < 0 || _playlist.isEmpty) return;
    _ensurePlayerInitialized();
    if (_isShuffleEnabled && _shuffleOrder.length == _playlist.length) {
      final pos = _shufflePos + 1 + autoIndex;
      if (pos >= _shuffleOrder.length) return;
      _shufflePos = pos;
      _currentIndex = _shuffleOrder[pos];
    } else {
      final idx = _currentIndex + 1 + autoIndex;
      if (idx >= _playlist.length) return;
      _currentIndex = idx;
    }
    _playingFromQueue = false;
    await _loadAndPlay(_playlist[_currentIndex]);
  }

  /// Reorder a track within the auto-upcoming section. In shuffle mode this
  /// reorders the upcoming shuffle sequence (until the next reshuffle); in
  /// sequential mode it reorders the playlist tail. Indices are relative to
  /// [upcomingFromContext].
  Future<void> reorderUpcoming(int oldAuto, int newAuto) async {
    if (oldAuto == newAuto) return;
    final shuffle = _isShuffleEnabled && _shuffleOrder.length == _playlist.length;
    final base = shuffle ? _shufflePos + 1 : _currentIndex + 1;
    final list = shuffle ? _shuffleOrder : _playlist;
    final oldPos = base + oldAuto;
    final newPos = base + newAuto;
    if (oldPos < base || oldPos >= list.length) return;
    if (newPos < base || newPos >= list.length) return;
    if (shuffle) {
      final v = _shuffleOrder.removeAt(oldPos);
      _shuffleOrder.insert(newPos, v);
    } else {
      final v = _playlist.removeAt(oldPos);
      _playlist.insert(newPos, v);
    }
    notifyListeners();
  }

  // -------- Modes --------

  Future<void> toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;
    if (_isShuffleEnabled && _playlist.length > 1) {
      _regenerateShuffleOrder(anchorAt: _currentIndex);
    }
    notifyListeners();
  }

  void toggleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        break;
    }
    notifyListeners();
  }

  /// ReplayGain pre-amp in dB. Middle-ground value picked to balance two
  /// competing goals:
  ///
  ///   • Equal loudness across tracks (low values → loud masters fully
  ///     attenuated to the ReplayGain reference)
  ///   • Acceptable overall volume (high values → less attenuation, library
  ///     plays louder, but the variance between tracks widens)
  ///
  /// Reference table for a track with rgTrackGain = -7 dB (typical pop
  /// master), since clamp(0..1) caps amplification at unity:
  ///   preamp 0 → factor 0.45  (-7 dB attenuation, full normalization)
  ///   preamp 3 → factor 0.63  (-4 dB attenuation, current setting)
  ///   preamp 6 → factor 0.89  (-1 dB attenuation, mostly untouched)
  static const double _replayGainPreAmpDb = 3.0;

  /// Linear playback multiplier derived from a track's ReplayGain (dB).
  /// Attenuate-only: after the pre-amp, tracks still louder than the target are
  /// turned down toward it; quieter tracks are never boosted (clamped at 1.0),
  /// so clipping is impossible. Tracks with no loudness data play unchanged.
  double _replayGainFactor(Track? track) {
    final db = track?.replayGainDb;
    if (db == null) return 1.0;
    final factor = pow(10, (db + _replayGainPreAmpDb) / 20).toDouble();
    return factor.clamp(0.0, 1.0).toDouble();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_player != null) {
      await _player!.setVolume(_volume * _replayGainFactor(_currentTrack));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _playingSubscription?.cancel();
    _playbackEventSubscription?.cancel();
    _player?.dispose();
    if (_isWindows) {
      WindowsWakelock.disable();
      _windowsMediaControls.dispose();
    }
    super.dispose();
  }
}
