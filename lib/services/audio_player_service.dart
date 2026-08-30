import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform, File, Directory;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import 'now_playing_presence.dart';
import 'playback_cursor.dart';
import 'playback_reporter.dart';
import 'stream_url_resolver.dart';

export 'playback_cursor.dart' show RepeatMode;

/// Plays one track at a time. All sequencing (playlist order, shuffle, loop,
/// queue) is handled by [PlaybackCursor] so we don't depend on just_audio's
/// ConcatenatingAudioSource — which is buggy on just_audio_media_kit
/// (Windows/Linux). This class is the adapter over just_audio: it asks the
/// cursor what plays next and is responsible for actually loading and
/// playing it. Telling the OS what's playing is [NowPlayingPresence]'s job;
/// minting the stream/cover URLs to play and show is [StreamUrlResolver]'s —
/// neither is this class's own concern. The user-facing API is unchanged.
class AudioPlayerService with ChangeNotifier {
  AudioPlayer? _player;
  final NowPlayingPresence _presence;
  final StreamUrlResolver _resolver;
  final PlaybackReporter _reporter;

  final PlaybackCursor _cursor = PlaybackCursor();
  // The track currently coming out of the speakers — may be a playlist item
  // or a queue item.
  Track? _currentTrack;

  double _volume = 1.0;
  String? _lastError;
  bool _isLoading = false;
  int _loadToken = 0;

  // Debounce for user-initiated skips: a burst of Next/Previous presses
  // updates the shown track instantly but coalesces into a single stream
  // load, so we open only the track the user lands on — not every one passed
  // through. Natural end-of-track advance bypasses this (loads immediately) to
  // stay gapless.
  static const _skipDebounce = Duration(milliseconds: 280);
  Timer? _loadDebounce;

  // Android-only on-disk stream cache (LockCachingAudioSource). Lets the player
  // seek within a local file (Navidrome's live HTTP stream isn't seekable for
  // VBR/FLAC/OGG) and avoids re-streaming on replay. Bounded by
  // [_audioCacheCapBytes]; oldest songs are evicted after each load.
  Directory? _audioCacheDir;
  static const int _audioCacheCapBytes = 2 * 1024 * 1024 * 1024; // 2 GB

  // Mid-stream drop recovery: bounded auto-resume of the current track when the
  // network/server closes a connection mid-playback.
  int _resumeAttempts = 0;
  String? _resumeTrackId;
  DateTime? _lastResumeAt;

  // Scrobbling: report a play once it passes the Last.fm-style threshold —
  // half the track, or four minutes, whichever comes first.
  static const double _scrobbleFraction = 0.5;
  static const Duration _scrobbleAfter = Duration(minutes: 4);

  // Identifies one *listen*. Bumped by _selectAndPlay — i.e. by every fresh
  // selection, including repeat-one relooping the same track, so a replay
  // counts again. Mid-stream drop recovery deliberately re-enters
  // _loadAndPlay *without* going through _selectAndPlay, so a dropped-and-
  // resumed track stays one listen and scrobbles once.
  int _listenSession = 0;
  int? _scrobbledSession;
  DateTime _listenStartedAt = DateTime.now();

  StreamSubscription<Duration>? _scrobbleSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  bool _playerInitialized = false;

  // Provide safe stream getters that return empty streams before init.
  static const _emptyDurationStream = Stream<Duration>.empty();
  static const _emptyNullDurationStream = Stream<Duration?>.empty();
  static const _emptyBoolStream = Stream<bool>.empty();

  Stream<Duration> get positionStream =>
      _player?.positionStream ?? _emptyDurationStream;
  Stream<Duration?> get durationStream =>
      _player?.durationStream ?? _emptyNullDurationStream;
  Stream<Duration> get bufferedPositionStream =>
      _player?.bufferedPositionStream ?? _emptyDurationStream;
  Stream<bool> get playingStream => _player?.playingStream ?? _emptyBoolStream;

  AudioPlayer? get player => _player;
  Track? get currentTrack => _currentTrack;
  List<Track> get playlist => _cursor.playlist;
  int get currentIndex => _cursor.currentIndex;
  List<Track> get queue => _cursor.queue;
  int get queueLength => _cursor.queueLength;

  /// The upcoming tracks from the browsing context (playlist), in play order
  /// and shuffle-aware, starting after the current playback position. Does not
  /// wrap around on repeat-all. Independent of the manual [queue].
  List<Track> get upcomingFromContext => _cursor.upcoming;
  bool get isLoading => _isLoading;
  bool get isShuffleEnabled => _cursor.isShuffleEnabled;
  RepeatMode get repeatMode => _cursor.repeatMode;
  double get volume => _volume;
  String? get lastError => _lastError;

  bool get isPlaying => _player?.playing ?? false;
  Duration? get duration => _player?.duration;
  Duration? get position => _player?.position;
  Duration? get bufferedPosition => _player?.bufferedPosition;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  AudioPlayerService({
    NowPlayingPresence? presence,
    StreamUrlResolver? resolver,
    PlaybackReporter? reporter,
  }) : _presence = presence ?? const NoPresence(),
       _resolver = resolver ?? const NoResolver(),
       _reporter = reporter ?? const NoPlaybackReporter() {
    // Fire-and-forget: the modes are cosmetic until something is actually
    // playing, and this service is constructed before login, so there is
    // nothing to block on.
    _restoreModes();
  }

  // Shuffle and repeat survive a restart. Persisted here rather than in
  // PlaybackCursor, which is deliberately plain Dart with no plugin
  // dependencies so it stays testable without a platform channel.
  static const _prefShuffle = 'playback.shuffleEnabled';
  static const _prefRepeat = 'playback.repeatMode';

  bool _disposed = false;

  Future<void> _restoreModes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shuffle = prefs.getBool(_prefShuffle);
      final repeatName = prefs.getString(_prefRepeat);
      if (shuffle != null) _cursor.setShuffle(shuffle);
      if (repeatName != null) {
        // A value written by a future version we don't know is ignored rather
        // than crashing — the cursor keeps its own default.
        for (final mode in RepeatMode.values) {
          if (mode.name == repeatName) {
            _cursor.setRepeatMode(mode);
            break;
          }
        }
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      // No shared_preferences implementation (widget tests) or unreadable
      // storage — the cursor's defaults are a perfectly good fallback.
    }
  }

  Future<void> _persistModes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefShuffle, _cursor.isShuffleEnabled);
      await prefs.setString(_prefRepeat, _cursor.repeatMode.name);
    } catch (_) {
      // Best-effort: failing to remember a toggle must never break playback.
    }
  }

  /// Lazily initialize the AudioPlayer and stream listeners.
  void _ensurePlayerInitialized() {
    if (_playerInitialized) return;
    _playerInitialized = true;

    _player = AudioPlayer();
    // We sequence manually, so always let the player report completion.
    _player!.setLoopMode(LoopMode.off);

    _presence.bind(_player!, (
      play: () => _player?.play(),
      pause: () => _player?.pause(),
      next: playNext,
      previous: playPrevious,
      stop: stop,
    ));

    _playingSubscription = _player!.playingStream.listen((playing) {
      if (_currentTrack != null) _presence.setPlaying(playing);
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

    _scrobbleSubscription = _player!.positionStream.listen(_maybeScrobble);
  }

  // -------- Scrobbling --------

  /// Submit the current track once playback passes the threshold.
  ///
  /// Driven off the position stream rather than track completion, so a track
  /// the user skips away from *after* hearing most of it still counts —
  /// waiting for `completed` would miss exactly those.
  ///
  /// Position, not accumulated listening time: scrubbing to the end therefore
  /// counts as a play. That is the simpler rule, it is what most Subsonic
  /// clients do, and over-counting a track you deliberately seeked through is
  /// the benign direction to err in. See docs/decisions.md.
  void _maybeScrobble(Duration position) {
    final track = _currentTrack;
    if (track == null || _scrobbledSession == _listenSession) return;

    // The player's own duration is authoritative once loaded; the track's
    // metadata covers the window before that where it is still null.
    final total =
        _player?.duration ??
        (track.durationSeconds != null
            ? Duration(seconds: track.durationSeconds!)
            : null);
    if (total == null || total <= Duration.zero) return;

    final half = Duration(
      microseconds: (total.inMicroseconds * _scrobbleFraction).round(),
    );
    final threshold = half < _scrobbleAfter ? half : _scrobbleAfter;
    if (position < threshold) return;

    _scrobbledSession = _listenSession;
    _report(
      'scrobble',
      () => _reporter.scrobble(track.id, startedAt: _listenStartedAt),
    );
  }

  /// Fire-and-forget a report to the server.
  ///
  /// Reporting is telemetry: a server that is slow, down, or simply doesn't
  /// implement the endpoint must never surface as a playback error, so this
  /// swallows everything to a debug line.
  void _report(String what, Future<void> Function() send) {
    unawaited(
      send().catchError((Object e) {
        debugPrint('AudioPlayerService: $what failed: $e');
      }),
    );
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
    await _loadAndPlay(track, token, resumeFrom: resumeFrom);
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  // -------- Source helpers --------

  MediaItem _buildMediaItem(Track track) {
    final coverUrl = _resolver.resolveCoverUrl(track);
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist ?? '',
      album: track.album ?? '',
      duration: track.durationSeconds != null
          ? Duration(seconds: track.durationSeconds!)
          : null,
      artUri: coverUrl != null ? Uri.parse(coverUrl) : null,
    );
  }

  AudioSource _buildSource(Track track) {
    final uri = Uri.parse(_resolver.buildStreamUrl(track.id));
    final tag = _buildMediaItem(track);
    // On Android, cache the stream to a per-song file so playback is seekable
    // (the live HTTP stream isn't) and replays don't re-fetch from the server.
    // Keyed by track id — NOT the URL, whose auth salt rotates on every build
    // and would otherwise defeat the cache. Desktop (media_kit) streams direct.
    if (_isAndroid && _audioCacheDir != null) {
      return LockCachingAudioSource(
        uri,
        tag: tag,
        cacheFile: File('${_audioCacheDir!.path}/${track.id}'),
      );
    }
    return AudioSource.uri(uri, tag: tag);
  }

  /// Resolve the Android stream-cache directory once. No-op off Android.
  Future<void> _ensureAudioCacheDir() async {
    if (!_isAndroid || _audioCacheDir != null) return;
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/audio_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      _audioCacheDir = dir;
    } catch (e) {
      debugPrint('AudioPlayerService: could not init audio cache dir: $e');
    }
  }

  /// Keep the Android stream cache under [_audioCacheCapBytes] by deleting the
  /// oldest cached songs. Never evicts the track currently loaded. Fire-and-
  /// forget; cache integrity is best-effort.
  Future<void> _evictAudioCacheIfNeeded() async {
    final dir = _audioCacheDir;
    if (dir == null) return;
    try {
      final entries = <({File file, int size, DateTime modified})>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final st = await e.stat();
        total += st.size;
        entries.add((file: e, size: st.size, modified: st.modified));
      }
      if (total <= _audioCacheCapBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified)); // oldest first
      final currentId = _currentTrack?.id;
      for (final entry in entries) {
        if (total <= _audioCacheCapBytes) break;
        if (currentId != null && entry.file.path.endsWith('/$currentId')) {
          continue; // don't delete the song that's playing
        }
        try {
          await entry.file.delete();
          total -= entry.size;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('AudioPlayerService: audio cache eviction failed: $e');
    }
  }

  /// Load the source, retrying once if it stalls. A single setAudioSource on
  /// the streaming backend (media_kit on Windows / the Android backend) can
  /// occasionally hang and never complete, which wedges playback ("freezes and
  /// never plays" on Next). Re-issuing the load recovers it — the same thing a
  /// manual Next press does, but automatic and on the same track.
  Future<void> _setSourceWithRetry(Track track, int token) async {
    await _ensureAudioCacheDir();
    const loadTimeout = Duration(seconds: 12);
    try {
      await _player!.setAudioSource(_buildSource(track)).timeout(loadTimeout);
    } on TimeoutException {
      // If a newer load superseded us while we were stalled, don't reissue —
      // retrying here would clobber the current track's source with this
      // stale one.
      if (token != _loadToken) return;
      debugPrint(
        'AudioPlayerService: load stalled, retrying trackId=${track.id}',
      );
      await _player!.setAudioSource(_buildSource(track)).timeout(loadTimeout);
    }
  }

  void _logStreamParams(Track track) {
    final uri = Uri.tryParse(_resolver.buildStreamUrl(track.id));
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

  /// Show [track] immediately (instant UI) and load it. A burst of user skips
  /// each calls this with [immediate] = false: the displayed track updates per
  /// press, but the stream open is debounced so only the track the user lands
  /// on is opened. Natural end-of-track advance passes [immediate] = true to
  /// load with no gap. Bumping [_loadToken] here invalidates any in-flight load
  /// at once, so a superseded track never reaches play().
  void _selectAndPlay(Track track, {required bool immediate}) {
    final token = ++_loadToken;
    // A fresh selection is a new listen — see [_listenSession]. Stamped here
    // rather than at load time so the server gets when the user *chose* the
    // track, not when its stream finished opening.
    _listenSession++;
    _listenStartedAt = DateTime.now();
    _currentTrack = track;
    _isLoading = true;
    _lastError = null;
    _loadDebounce?.cancel();
    notifyListeners();

    if (immediate) {
      _loadDebounce = null;
      _loadAndPlay(track, token);
    } else {
      _loadDebounce = Timer(_skipDebounce, () {
        _loadDebounce = null;
        _loadAndPlay(track, token);
      });
    }
  }

  /// Load [track] as the single audio source and start playback, guarded by
  /// [token] (assigned in [_selectAndPlay] or [_handleStreamError]) against
  /// rapid successive calls. Pass [resumeFrom] to seek there once loaded —
  /// [_handleStreamError] uses this to resume a dropped stream where it left
  /// off; a fresh track selection never passes one.
  Future<void> _loadAndPlay(
    Track track,
    int token, {
    Duration? resumeFrom,
  }) async {
    try {
      _logStreamParams(track);
      await _setSourceWithRetry(track, token);
      if (token != _loadToken) return;
      await _player!.setVolume(_volume * _replayGainFactor(track));
      if (resumeFrom != null && resumeFrom > Duration.zero) {
        await _player!.seek(resumeFrom);
      }
      await _player!.play();
      _presence.show(track);
      // Same moment we tell the OS, tell the server — this drives Navidrome's
      // "now playing" panel. Re-sent on drop recovery, which is fine: it is a
      // heartbeat, not a play count.
      _report('now-playing', () => _reporter.nowPlaying(track.id));
      unawaited(_evictAudioCacheIfNeeded());
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

  /// What [playNext] would play right now — without mutating shuffle state.
  /// Used by the player screen to precache the next track's cover art so the
  /// transition between tracks doesn't flash an empty/loading frame. Returns
  /// null when end-of-playlist (repeat off) would stop playback.
  Track? peekNextTrack() => _cursor.peekNext();

  // -------- Playback entry points --------

  /// Play a single track. Replaces the playlist context but preserves the
  /// user-built queue — switching the current song should not discard songs
  /// the user has explicitly lined up to play next.
  Future<void> playTrack(Track track) async {
    _ensurePlayerInitialized();
    _selectAndPlay(_cursor.start([track], at: 0), immediate: true);
  }

  /// Play [tracks] starting from [from]. Preserves the user-built queue so
  /// switching songs doesn't discard queued tracks.
  Future<void> play(List<Track> tracks, {int from = 0}) async {
    if (tracks.isEmpty) return;
    if (from < 0 || from >= tracks.length) return;
    _ensurePlayerInitialized();
    _selectAndPlay(_cursor.start(tracks, at: from), immediate: true);
  }

  /// Shuffle-play [tracks]: turns shuffle on (if it wasn't already) and
  /// starts from a random track. Replaces the toggleShuffle()-then-play(-1)
  /// protocol every call site used to hand-assemble.
  Future<void> playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    _ensurePlayerInitialized();
    _cursor.setShuffle(true);
    final start = tracks.length > 1 ? Random().nextInt(tracks.length) : 0;
    _selectAndPlay(_cursor.start(tracks, at: start), immediate: true);
  }

  Future<void> _onTrackCompleted() async {
    if (_cursor.repeatMode == RepeatMode.one && _currentTrack != null) {
      _selectAndPlay(_currentTrack!, immediate: true);
      return;
    }
    await _advance(immediate: true);
  }

  /// User-pressed "next". Debounced: a rapid burst advances the cursor (and
  /// the shown track) per press but opens only the final track's stream.
  Future<void> playNext() => _advance(immediate: false);

  /// Advance to the next track. Queue takes priority over playlist
  /// advancement, regardless of shuffle. [immediate] = true is used for
  /// natural end-of-track advance (gapless); user skips pass false to debounce.
  Future<void> _advance({required bool immediate}) async {
    _ensurePlayerInitialized();
    final next = _cursor.advance();
    if (next == null) {
      await stop();
      return;
    }
    _selectAndPlay(next, immediate: immediate);
  }

  /// Previous from a queue item returns to the playlist track that was
  /// interrupted. Previous from a playlist track steps one back in the
  /// playlist (or shuffle order).
  Future<void> playPrevious() async {
    _ensurePlayerInitialized();
    final prev = _cursor.rewind();
    if (prev == null) return;
    _selectAndPlay(prev, immediate: false);
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
    _cursor.clearQueue();
    _presence.clear();
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
    _cursor.enqueue(track);
    notifyListeners();
  }

  Future<void> removeFromQueue(int queueIndex) async {
    if (_cursor.dequeueAt(queueIndex)) notifyListeners();
  }

  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    if (_cursor.moveInQueue(oldIndex, newIndex)) notifyListeners();
  }

  /// Play the manual-queue track at [queueIndex] now, discarding the queued
  /// tracks ahead of it (the ones that would have played first).
  Future<void> jumpToQueued(int queueIndex) async {
    final track = _cursor.jumpToQueued(queueIndex);
    if (track == null) return;
    _ensurePlayerInitialized();
    _selectAndPlay(track, immediate: true);
  }

  /// Jump forward to the [autoIndex]-th track of [upcomingFromContext]. The
  /// cursor simply moves; skipped tracks are not removed and remain reachable
  /// via Previous.
  Future<void> jumpToUpcoming(int autoIndex) async {
    final next = _cursor.jumpToUpcoming(autoIndex);
    if (next == null) return;
    _ensurePlayerInitialized();
    _selectAndPlay(next, immediate: true);
  }

  /// Reorder a track within the auto-upcoming section. In shuffle mode this
  /// reorders the upcoming shuffle sequence (until the next reshuffle); in
  /// sequential mode it reorders the playlist tail. Indices are relative to
  /// [upcomingFromContext].
  Future<void> reorderUpcoming(int oldAuto, int newAuto) async {
    if (_cursor.reorderUpcoming(oldAuto, newAuto)) notifyListeners();
  }

  // -------- Modes --------

  Future<void> toggleShuffle() async {
    _cursor.toggleShuffle();
    notifyListeners();
    await _persistModes();
  }

  /// Set shuffle to a known state, rather than flipping it — for callers
  /// that want "shuffle on" as an outcome, not a toggle.
  void setShuffle(bool enabled) {
    _cursor.setShuffle(enabled);
    notifyListeners();
    _persistModes();
  }

  void toggleRepeatMode() {
    _cursor.toggleRepeatMode();
    notifyListeners();
    _persistModes();
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
  ///   preamp 3 → factor 0.63  (-4 dB attenuation)
  ///   preamp 6 → factor 0.89  (-1 dB attenuation, current setting — plays
  ///                            louder, near the file's own level)
  ///   preamp 9 → factor 1.00  (no attenuation; loudest, leveling effectively
  ///                            off — bump here if you want it louder still)
  static const double _replayGainPreAmpDb = 6.0;

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

  /// Test-only seam onto [_replayGainFactor] — the math is pure, but the
  /// method itself is private (Dart privacy is per-library, so a test file
  /// can't reach it directly).
  @visibleForTesting
  double replayGainFactorForTest(Track? track) => _replayGainFactor(track);

  /// Test-only seam: seeds playback state directly instead of going through
  /// [playTrack]/[play], which lazily construct a real [AudioPlayer]
  /// and therefore need a live platform audio backend. Lets widget tests
  /// render UI driven by this service (mini player, queue sheet) against
  /// realistic state without one, and lets sequencing tests set up scenarios
  /// no production entry point produces on its own. Never touches the player.
  @visibleForTesting
  void seedForTest({
    List<Track>? playlist,
    int? currentIndex,
    List<Track>? queue,
    Track? currentTrack,
    bool? isShuffleEnabled,
    RepeatMode? repeatMode,
    List<int>? shuffleOrder,
    int? shufflePos,
  }) {
    // PlaybackCursor.seed is itself a test-only seam; this method (also
    // @visibleForTesting) is its sole production-code caller, wrapping it
    // the same way replayGainFactorForTest wraps _replayGainFactor above —
    // the analyzer just can't see through one test seam calling another.
    // ignore: invalid_use_of_visible_for_testing_member
    _cursor.seed(
      playlist: playlist,
      currentIndex: currentIndex,
      queue: queue,
      isShuffleEnabled: isShuffleEnabled,
      repeatMode: repeatMode,
      shuffleOrder: shuffleOrder,
      shufflePos: shufflePos,
    );
    if (currentTrack != null) _currentTrack = currentTrack;
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_player != null) {
      await _player!.setVolume(_volume * _replayGainFactor(_currentTrack));
    }
    notifyListeners();
  }

  /// Tear everything down and *wait* for the native player to actually stop.
  ///
  /// [dispose] cannot do this: it is `ChangeNotifier`'s, and it is synchronous,
  /// so it can only fire-and-forget the player's disposal. On desktop the
  /// native player (mpv, via media_kit) runs its own thread holding FFI
  /// callbacks into Dart — if the process exits while that thread is alive, the
  /// next event it delivers calls into a dead isolate and the app dumps core on
  /// close. See the shutdown-crash trap in `docs/operations.md`.
  ///
  /// Idempotent, and safe to call before [dispose] — which is exactly what
  /// happens on desktop: this runs on window close, Provider's [dispose] never
  /// runs at all.
  Future<void> shutdown() => _teardown() ?? Future.value();

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  /// Releases everything held here exactly once. Returns the native player's
  /// disposal future so [shutdown] can await it, or null if there is nothing
  /// left to release.
  Future<void>? _teardown() {
    if (_disposed) return null;
    _disposed = true;
    _loadDebounce?.cancel();
    _scrobbleSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playingSubscription?.cancel();
    _playbackEventSubscription?.cancel();
    _presence.dispose();
    // Cleared before the await so nothing can reach a half-disposed player.
    final player = _player;
    _player = null;
    return player?.dispose();
  }
}
