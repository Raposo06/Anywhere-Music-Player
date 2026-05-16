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

enum RepeatMode { off, all, one }

class AudioPlayerService with ChangeNotifier {
  AudioPlayer? _player;
  final MusicAudioHandler? _audioHandler;
  final WindowsMediaControlsService _windowsMediaControls =
      WindowsMediaControlsService.instance;
  Track? _currentTrack;
  List<Track> _playlist = [];
  int _currentIndex = -1;
  bool _isLoading = false;
  int _loadToken = 0;
  bool _isShuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.all;
  double _volume = 1.0;
  String? _lastError;
  StreamSubscription<SequenceState?>? _sequenceStateSubscription;
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
  Stream<bool> get playingStream =>
      _player?.playingStream ?? _emptyBoolStream;

  AudioPlayer? get player => _player;
  Track? get currentTrack => _currentTrack;
  List<Track> get playlist => _playlist;
  int get currentIndex => _currentIndex;
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
              isPlaying: _player?.playing ?? false);
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

  /// Lazily initialize the AudioPlayer and all stream listeners.
  void _ensurePlayerInitialized() {
    if (_playerInitialized) return;
    _playerInitialized = true;

    _player = AudioPlayer();
    _player!.setLoopMode(_loopModeFor(_repeatMode));
    _player!.setShuffleModeEnabled(_isShuffleEnabled);

    // Attach player to the pre-initialized audio handler (Android/iOS only)
    if (_audioHandler != null) {
      _audioHandler!.attachPlayer(
        player: _player!,
        onNextCallback: playNext,
        onPreviousCallback: playPrevious,
      );
    }

    // Notify UI on play/pause state changes.
    _playingSubscription = _player!.playingStream.listen((playing) {
      if (_isWindows && _currentTrack != null) {
        _windowsMediaControls.updatePlaybackStatus(isPlaying: playing);
      }
      notifyListeners();
    });

    // Keep our track pointer synced with the player. SequenceState.currentIndex
    // is the source index; the player follows the shuffle order internally
    // when shuffle mode is enabled.
    _sequenceStateSubscription =
        _player!.sequenceStateStream.listen((state) {
      if (state == null || _playlist.isEmpty) return;
      final index = state.currentIndex;
      if (index != _currentIndex &&
          index >= 0 &&
          index < _playlist.length) {
        _currentIndex = index;
        _currentTrack = _playlist[_currentIndex];
        if (_audioHandler != null) {
          _audioHandler!.updateTrackInfo(_currentTrack!);
        }
        _updateWindowsMetadata(_currentTrack);
        notifyListeners();
      }
    });

    // With LoopMode.all / LoopMode.one set on the player, repeat is handled
    // natively and ProcessingState.completed never fires mid-playlist.
    // Completion therefore only fires when LoopMode.off reaches the end.
    _playerStateSubscription = _player!.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && !_isLoading) {
        stop();
      }
    });

    // Listen for playback errors.
    _playbackEventSubscription = _player!.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        _handlePlaybackError(e);
      },
    );
  }

  LoopMode _loopModeFor(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return LoopMode.off;
      case RepeatMode.all:
        return LoopMode.all;
      case RepeatMode.one:
        return LoopMode.one;
    }
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
    final errorStr = error.toString();
    _lastError = 'Playback error: $errorStr';
    debugPrint('Playback error: $errorStr');
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  ConcatenatingAudioSource _buildPlaylistSource(List<Track> tracks) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: tracks
          .map((track) => AudioSource.uri(
                Uri.parse(track.streamUrl),
                tag: MediaItem(
                  id: track.id,
                  title: track.title,
                  artist: '',
                  duration: track.durationSeconds != null
                      ? Duration(seconds: track.durationSeconds!)
                      : null,
                  artUri: track.coverArtUrl != null
                      ? Uri.parse(track.coverArtUrl!)
                      : null,
                ),
              ))
          .toList(),
    );
  }

  /// Set the audio source and start playback.
  Future<void> _setSourceAndPlay(AudioSource source,
      {int? initialIndex}) async {
    if (initialIndex != null) {
      await _player!.setAudioSource(source, initialIndex: initialIndex);
    } else {
      await _player!.setAudioSource(source);
    }
    _player!.play();
  }

  /// Play a single track.
  Future<void> playTrack(Track track) async {
    _ensurePlayerInitialized();
    _lastError = null;
    final token = ++_loadToken;

    _isLoading = true;
    _currentTrack = track;
    _playlist = [track];
    _currentIndex = 0;
    notifyListeners();

    try {
      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(track);
      }

      final source = _buildPlaylistSource([track]);
      await _setSourceAndPlay(source);
      if (token != _loadToken) return;
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

  /// Play a playlist. Pass [startIndex] = -1 to let shuffle pick the first
  /// track at random, or use a specific index otherwise.
  Future<void> playPlaylist(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    if (startIndex != -1 && (startIndex < 0 || startIndex >= tracks.length)) {
      return;
    }

    _ensurePlayerInitialized();
    _lastError = null;
    final token = ++_loadToken;

    _isLoading = true;
    _playlist = List.from(tracks);

    // Resolve the starting source-index. When no track was specified and
    // shuffle is on, pick a random one so playback opens on something fresh.
    final int resolvedStart;
    if (startIndex >= 0) {
      resolvedStart = startIndex;
    } else if (_isShuffleEnabled && tracks.length > 1) {
      resolvedStart = Random().nextInt(tracks.length);
    } else {
      resolvedStart = 0;
    }
    _currentIndex = resolvedStart;
    _currentTrack = _playlist[_currentIndex];
    notifyListeners();

    try {
      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(_currentTrack!);
      }

      final source = _buildPlaylistSource(_playlist);
      await _player!.setShuffleModeEnabled(_isShuffleEnabled);
      await _player!.setAudioSource(source, initialIndex: resolvedStart);
      if (_isShuffleEnabled) {
        // Regenerate the shuffle order so the chosen track plays first and
        // seekToNext follows a fresh random sequence.
        await source.shuffle(initialIndex: resolvedStart);
      }

      _player!.play();

      if (token != _loadToken) return;
      _updateWindowsMetadata(_currentTrack);
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

  /// Play next track. Respects shuffle and loop mode set on the player.
  Future<void> playNext() async {
    if (_playlist.isEmpty || _player == null) return;
    _ensurePlayerInitialized();
    _lastError = null;

    if (_player!.hasNext) {
      await _player!.seekToNext();
      if (!_player!.playing) _player!.play();
    } else {
      await stop();
    }
  }

  /// Play previous track. Respects shuffle and loop mode set on the player.
  Future<void> playPrevious() async {
    if (_playlist.isEmpty || _player == null) return;
    _ensurePlayerInitialized();
    _lastError = null;

    if (_player!.hasPrevious) {
      await _player!.seekToPrevious();
      if (!_player!.playing) _player!.play();
    }
  }

  /// Toggle play/pause.
  Future<void> togglePlayPause() async {
    if (_player == null) return;
    if (_player!.playing) {
      await _player!.pause();
    } else {
      _player!.play();
    }
  }

  /// Stop playback and clear current track.
  Future<void> stop() async {
    if (_player != null) {
      await _player!.stop();
    }
    _currentTrack = null;
    _updateWindowsMetadata(null);
    if (_isWindows) {
      _windowsMediaControls.clear();
    }
    notifyListeners();
  }

  /// Toggle shuffle mode. The player handles reordering natively — no need to
  /// rebuild the audio source or duplicate the playlist.
  Future<void> toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_player != null) {
      try {
        await _player!.setShuffleModeEnabled(_isShuffleEnabled);
        if (_isShuffleEnabled) {
          final source = _player!.audioSource;
          if (source is ConcatenatingAudioSource && _currentIndex >= 0) {
            // Regenerate the shuffle order so the current track plays first.
            await source.shuffle(initialIndex: _currentIndex);
          }
        }
      } catch (e) {
        debugPrint('Error toggling shuffle: $e');
      }
    }

    notifyListeners();
  }

  /// Toggle repeat mode (off -> all -> one -> off).
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
    _player?.setLoopMode(_loopModeFor(_repeatMode));
    notifyListeners();
  }

  /// Set volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_player != null) {
      await _player!.setVolume(_volume);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sequenceStateSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playingSubscription?.cancel();
    _playbackEventSubscription?.cancel();
    _player?.dispose();
    if (_isWindows) {
      _windowsMediaControls.dispose();
    }
    super.dispose();
  }
}
