import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/track.dart';
import 'audio_handler.dart';
import 'windows_media_controls_service.dart';

enum RepeatMode { off, all, one }

class AudioPlayerService with ChangeNotifier {
  late final AudioPlayer _player;
  final MusicAudioHandler? _audioHandler;
  final WindowsMediaControlsService _windowsMediaControls = WindowsMediaControlsService.instance;
  Track? _currentTrack;
  List<Track> _playlist = [];
  List<Track> _originalPlaylist = [];
  int _currentIndex = -1;
  bool _isLoading = false;
  bool _isSeeking = false;
  bool _isSkipping = false;
  bool _isRebuildingSource = false;
  int _skipToken = 0;
  int _loadToken = 0;
  bool _isShuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.all;
  double _volume = 1.0; // 0.0 to 1.0
  String? _lastError;
  /// Offset applied when using timeOffset-based seeking.
  /// When the stream is reloaded with timeOffset=N, the player reports
  /// position from 0, but the real position is _seekOffset + playerPosition.
  Duration _seekOffset = Duration.zero;
  final _random = Random();
  StreamSubscription<int?>? _indexStreamSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;

  /// Streams exposed for UI widgets that need high-frequency updates (e.g., progress bar).
  /// Using streams instead of notifyListeners() avoids rebuilding the entire widget tree.
  /// Position stream adds _seekOffset to account for timeOffset-based seeking.
  Stream<Duration> get positionStream =>
      _player.positionStream.map((pos) => pos + _seekOffset);
  Stream<Duration?> get durationStream => _player.durationStream.map((dur) {
    if (dur == null) return null;
    // When using timeOffset, the reported duration is shorter (remaining time).
    // Add the offset back so the UI shows the full track duration.
    if (_seekOffset > Duration.zero) {
      final track = _currentTrack;
      if (track?.durationSeconds != null) {
        return Duration(seconds: track!.durationSeconds!);
      }
    }
    return dur;
  });
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<bool> get playingStream => _player.playingStream;

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentTrack;
  List<Track> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  bool get isSeeking => _isSeeking;
  bool get isShuffleEnabled => _isShuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  double get volume => _volume;
  String? get lastError => _lastError;

  bool get isPlaying => _player.playing;
  Duration? get duration => _player.duration;
  Duration? get position => _player.position != null ? _player.position! + _seekOffset : null;
  Duration? get bufferedPosition => _player.bufferedPosition;

  /// Check if we're running on Windows
  bool get _isWindows => !kIsWeb && Platform.isWindows;

  AudioPlayerService({MusicAudioHandler? audioHandler})
      : _audioHandler = audioHandler {
    // Initialize audio player
    _player = AudioPlayer();

    // Attach player to the pre-initialized audio handler
    if (_audioHandler != null) {
      _audioHandler!.attachPlayer(
        player: _player,
        onNextCallback: playNext,
        onPreviousCallback: playPrevious,
      );
      debugPrint('Audio handler attached to player');
    }

    // Initialize Windows media controls for keyboard support
    _initializeWindowsMediaControls();

    // Only notify on discrete state changes (play/pause), not high-frequency streams.
    _playingSubscription = _player.playingStream.listen((playing) {
      if (_isWindows) {
        _windowsMediaControls.updatePlaybackStatus(isPlaying: playing);
      }
      notifyListeners();
    });

    // Handle playlist completion and repeat modes.
    // Only act on genuine end-of-playlist, not transient completed states
    // that occur during seek/skip operations.
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && !_isSkipping && !_isSeeking) {
        _handleCompletion();
      }
    });

    // Listen for playback errors (constructor continues)
    _playbackEventSubscription = _player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        _handlePlaybackError(e);
      },
    );
  }

  /// Handle playlist completion with proper error handling.
  /// Called when the player reaches ProcessingState.completed and we're not
  /// in the middle of a skip or seek operation.
  /// Also verifies the position is actually near the end of the track to avoid
  /// false completions triggered by seeking in network streams.
  Future<void> _handleCompletion() async {
    // Verify this is a genuine completion: position should be near the track's end.
    final pos = _player.position;
    final dur = _player.duration;
    if (dur != null && dur.inSeconds > 0) {
      final remaining = dur - pos;
      if (remaining.inSeconds > 3) {
        // Position is not near the end — this is a false completion (e.g. from seek).
        // Restart playback from current position instead of treating as end-of-track.
        debugPrint('Ignoring false completion: position=$pos, duration=$dur, remaining=${remaining.inSeconds}s');
        await _player.play();
        return;
      }
    }

    _seekOffset = Duration.zero; // Reset offset on track completion
    final isLastTrack = _currentIndex >= _playlist.length - 1;

    try {
      if (_repeatMode == RepeatMode.one) {
        // Replay current track from the beginning
        await _restorePlaylist(_currentIndex);
      } else if (isLastTrack) {
        if (_repeatMode == RepeatMode.all && _playlist.isNotEmpty) {
          // Wrap to first track
          _currentIndex = 0;
          _currentTrack = _playlist[0];
          if (_audioHandler != null) {
            _audioHandler!.updateTrackInfo(_currentTrack!);
          }
          notifyListeners();
          await _restorePlaylist(0);
        }
        // For repeat-off on last track: do nothing — player stops.
      } else if (_needsPlaylistRestore) {
        // Not the last track, but the ConcatenatingAudioSource was replaced
        // by a single source (timeOffset seek), so auto-advance doesn't work.
        // Manually advance to the next track and restore the playlist.
        _currentIndex++;
        _currentTrack = _playlist[_currentIndex];
        if (_audioHandler != null) {
          _audioHandler!.updateTrackInfo(_currentTrack!);
        }
        notifyListeners();
        await _restorePlaylist(_currentIndex);
      }
    } catch (e) {
      debugPrint('Error handling playlist completion: $e');
    }
  }

  /// Initialize Windows media controls for keyboard support (Fn+F5/F6/F7)
  Future<void> _initializeWindowsMediaControls() async {
    if (!_isWindows) return;

    try {
      await _windowsMediaControls.initialize(
        onPlay: () {
          _player.play();
        },
        onPause: () {
          _player.pause();
        },
        onNext: () {
          playNext();
        },
        onPrevious: () {
          playPrevious();
        },
        onStop: () {
          stop();
        },
      );
    } catch (e) {
      debugPrint('Failed to initialize Windows media controls: $e');
    }
  }

  /// Handle playback errors with platform-specific messages
  void _handlePlaybackError(Object error) {
    final errorStr = error.toString();

    if (_isWindows && errorStr.contains('Media error')) {
      _lastError = 'Windows playback error. The audio format may not be supported.';
    } else {
      _lastError = 'Playback error: $errorStr';
    }
    debugPrint('Playback error: $errorStr');
    notifyListeners();
  }

  /// Clear the last error
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Build a ConcatenatingAudioSource from a list of tracks for gapless playback.
  ConcatenatingAudioSource _buildPlaylistSource(List<Track> tracks) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: tracks.map((track) => AudioSource.uri(
        Uri.parse(track.streamUrl),
        tag: MediaItem(
          id: track.id,
          title: track.title,
          artist: track.artist ?? 'Unknown Artist',
          duration: track.durationSeconds != null
              ? Duration(seconds: track.durationSeconds!)
              : null,
          artUri: track.coverArtUrl != null ? Uri.parse(track.coverArtUrl!) : null,
        ),
      )).toList(),
    );
  }

  /// Play a single track.
  /// Safe to call rapidly — only the last-tapped track loads.
  Future<void> playTrack(Track track) async {
    _lastError = null;
    _seekOffset = Duration.zero;
    final token = ++_loadToken;

    _isLoading = true;
    _currentTrack = track;
    _playlist = [track];
    _currentIndex = 0;
    // Cancel stale playlist index listener — single-track mode doesn't need it
    _indexStreamSubscription?.cancel();
    _indexStreamSubscription = null;
    notifyListeners();

    try {
      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(track);
      }

      final source = _buildPlaylistSource([track]);
      await _player.setAudioSource(source);
      if (token != _loadToken) return;
      await _player.play();
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

  /// Set a playlist and play from a specific index using ConcatenatingAudioSource
  /// for gapless playback.
  /// Safe to call rapidly — only the last call takes effect.
  Future<void> playPlaylist(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) {
      return;
    }

    _lastError = null;
    _seekOffset = Duration.zero;
    final token = ++_loadToken;

    _isLoading = true;
    _originalPlaylist = List.from(tracks);
    _playlist = List.from(tracks);

    if (_isShuffleEnabled) {
      _shufflePlaylist(startIndex);
    } else {
      _currentIndex = startIndex;
    }

    _currentTrack = _playlist[_currentIndex];
    notifyListeners();

    try {
      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(_currentTrack!);
      }

      final source = _buildPlaylistSource(_playlist);
      await _player.setAudioSource(source, initialIndex: _currentIndex);
      if (token != _loadToken) return;
      await _player.play();

      // Cancel previous listener to prevent leaks
      _indexStreamSubscription?.cancel();
      // Listen for track changes within the concatenating source
      _indexStreamSubscription = _player.currentIndexStream.listen((index) {
        if (index != null && index != _currentIndex && index < _playlist.length && !_isRebuildingSource && !_isSkipping) {
          _currentIndex = index;
          _seekOffset = Duration.zero; // Reset offset when track changes
          _currentTrack = _playlist[_currentIndex];
          if (_audioHandler != null) {
            _audioHandler!.updateTrackInfo(_currentTrack!);
          }
          notifyListeners();
        }
      });
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

  /// Whether the audio source was replaced by a single-track seek (timeOffset).
  bool get _needsPlaylistRestore =>
      _playlist.length > 1 && _player.audioSource is! ConcatenatingAudioSource;

  /// Play next track in playlist.
  Future<void> playNext() async {
    if (_playlist.isEmpty) return;

    _lastError = null;
    _seekOffset = Duration.zero;

    if (_currentIndex >= _playlist.length - 1) {
      if (_repeatMode == RepeatMode.all) {
        _currentIndex = 0;
      } else {
        await stop();
        return;
      }
    } else {
      _currentIndex++;
    }

    _currentTrack = _playlist[_currentIndex];
    notifyListeners();

    if (_needsPlaylistRestore) {
      await _restorePlaylist(_currentIndex);
    } else {
      await _skipToIndex(_currentIndex);
    }
  }

  /// Play previous track in playlist.
  Future<void> playPrevious() async {
    if (_playlist.isEmpty || _currentIndex <= 0) return;

    _lastError = null;
    _seekOffset = Duration.zero;
    _currentIndex--;

    _currentTrack = _playlist[_currentIndex];
    notifyListeners();

    if (_needsPlaylistRestore) {
      await _restorePlaylist(_currentIndex);
    } else {
      await _skipToIndex(_currentIndex);
    }
  }

  /// Internal: skip to a specific index in the playlist, guarding against
  /// transient completed states that fire during seek.
  /// Uses a token so that rapid calls cancel stale in-flight seeks.
  Future<void> _skipToIndex(int index) async {
    final token = ++_skipToken;
    _isLoading = true;
    _isSkipping = true;

    try {
      if (_audioHandler != null && _currentTrack != null) {
        _audioHandler!.updateTrackInfo(_currentTrack!);
      }

      // Guard: ensure the player has an audio source before seeking.
      if (_player.audioSource == null) return;

      await _player.seek(Duration.zero, index: index);
      // If another skip came in while we were awaiting, bail out —
      // the newer call will handle playback.
      if (token != _skipToken) return;
      if (!_player.playing) {
        await _player.play();
      }
    } catch (e) {
      if (token != _skipToken) return;
      if (!e.toString().contains('Loading interrupted')) {
        _handlePlaybackError(e);
      }
    } finally {
      if (token == _skipToken) {
        _isLoading = false;
        _isSkipping = false;
        notifyListeners();
      }
    }
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// Seek to a specific absolute position within the current track.
  /// The [position] is the absolute position in the track (e.g., 2:30 of 5:00).
  /// First tries a normal seek (works if server supports HTTP Range requests).
  /// If that doesn't work, falls back to reloading the stream with Subsonic's
  /// timeOffset parameter for server-side seeking.
  Future<void> seek(Duration position) async {
    if (_currentTrack == null || _playlist.isEmpty) return;

    _isSeeking = true;

    try {
      // Convert absolute position to player-relative position
      // (accounting for any existing timeOffset from a previous seek)
      final playerTarget = position - _seekOffset;

      // Only try normal seek if there's no timeOffset active
      // (if timeOffset is active, the player's timeline is shifted and
      //  normal seek can only go within the remaining portion)
      if (_seekOffset == Duration.zero) {
        await _player.seek(position);
        await Future.delayed(const Duration(milliseconds: 200));

        final positionAfter = _player.position;
        final seekWorked = (positionAfter - position).abs() < const Duration(seconds: 3);

        if (seekWorked || position.inSeconds == 0) {
          return; // Normal seek worked
        }
        debugPrint('Standard seek failed (pos=$positionAfter, target=$position). '
            'Falling back to timeOffset reload.');
      }

      // Fall back to reloading with timeOffset
      await _seekViaReload(position);
    } catch (e) {
      debugPrint('Seek error: $e');
      try {
        await _seekViaReload(position);
      } catch (e2) {
        debugPrint('Seek reload fallback also failed: $e2');
      }
    } finally {
      _isSeeking = false;
    }
  }

  /// Fallback seek: reload just the current track with timeOffset parameter.
  /// Uses a single AudioSource (not ConcatenatingAudioSource) to avoid
  /// breaking playlist state. Next/previous are handled by the service.
  Future<void> _seekViaReload(Duration position) async {
    final track = _currentTrack!;
    final offsetSeconds = position.inSeconds;

    // Build a single-track source with timeOffset
    var url = track.streamUrl;
    if (offsetSeconds > 0) {
      url = url.contains('?')
          ? '$url&timeOffset=$offsetSeconds'
          : '$url?timeOffset=$offsetSeconds';
    }

    final source = AudioSource.uri(
      Uri.parse(url),
      tag: MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist ?? 'Unknown Artist',
        duration: track.durationSeconds != null
            ? Duration(seconds: track.durationSeconds!)
            : null,
        artUri: track.coverArtUrl != null ? Uri.parse(track.coverArtUrl!) : null,
      ),
    );

    _isRebuildingSource = true;
    await _player.setAudioSource(source);
    _seekOffset = position;
    _isRebuildingSource = false;
    await _player.play();
  }

  /// Rebuild and restore the full ConcatenatingAudioSource playlist
  /// (e.g. after a timeOffset seek replaced it with a single source).
  Future<void> _restorePlaylist(int startIndex) async {

    _isRebuildingSource = true;
    final source = _buildPlaylistSource(_playlist);
    await _player.setAudioSource(source, initialIndex: startIndex);
    _isRebuildingSource = false;

    // Re-subscribe to index changes for auto-advance
    _indexStreamSubscription?.cancel();
    _indexStreamSubscription = _player.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex && index < _playlist.length && !_isRebuildingSource && !_isSkipping) {
        _currentIndex = index;
        _seekOffset = Duration.zero;
        _currentTrack = _playlist[_currentIndex];
        if (_audioHandler != null) {
          _audioHandler!.updateTrackInfo(_currentTrack!);
        }
        notifyListeners();
      }
    });

    await _player.play();
  }

  /// Stop playback and clear current track
  Future<void> stop() async {
    await _player.stop();
    _currentTrack = null;
    if (_isWindows) {
      _windowsMediaControls.clear();
    }
    notifyListeners();
  }

  /// Toggle shuffle mode and rebuild the audio source to match the new order.
  Future<void> toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_playlist.isNotEmpty && _currentTrack != null) {
      final wasPlaying = _player.playing;
      final currentPosition = _player.position;

      if (_isShuffleEnabled) {
        final currentTrackIndex = _playlist.indexOf(_currentTrack!);
        if (currentTrackIndex >= 0) {
          _shufflePlaylist(currentTrackIndex);
        }
      } else {
        if (_originalPlaylist.isNotEmpty) {
          _playlist = List.from(_originalPlaylist);
          final index = _playlist.indexWhere((t) => t.id == _currentTrack!.id);
          if (index >= 0) {
            _currentIndex = index;
          }
        }
      }

      // Rebuild the audio source to match the new playlist order
      try {
        _isRebuildingSource = true;
        final source = _buildPlaylistSource(_playlist);
        await _player.setAudioSource(source, initialIndex: _currentIndex);
        await _player.seek(currentPosition);
        _isRebuildingSource = false;
        if (wasPlaying) {
          await _player.play();
        }
      } catch (e) {
        _isRebuildingSource = false;
        debugPrint('Error rebuilding playlist after shuffle toggle: $e');
      }
    }

    notifyListeners();
  }

  /// Toggle repeat mode (off -> all -> one -> off)
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

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    notifyListeners();
  }

  /// Shuffle the playlist, keeping the track at startIndex at position 0
  void _shufflePlaylist(int startIndex) {
    if (_playlist.isEmpty) return;

    final firstTrack = _playlist[startIndex];
    _playlist.removeAt(startIndex);
    _playlist.shuffle(_random);
    _playlist.insert(0, firstTrack);
    _currentIndex = 0;
  }

  @override
  void dispose() {
    _indexStreamSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playingSubscription?.cancel();
    _playbackEventSubscription?.cancel();
    _player.dispose();
    if (_isWindows) {
      _windowsMediaControls.dispose();
    }
    super.dispose();
  }
}
