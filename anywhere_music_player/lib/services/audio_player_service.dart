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
  List<Track> _originalPlaylist = [];
  int _currentIndex = -1;
  bool _isLoading = false;
  bool _isSkipping = false;
  int _skipToken = 0;
  int _loadToken = 0;
  bool _isShuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.all;
  double _volume = 1.0;
  String? _lastError;
  final _random = Random();
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

    // Track auto-advance via ConcatenatingAudioSource.
    _sequenceStateSubscription =
        _player!.sequenceStateStream.listen((state) {
      if (state == null || _isSkipping || _playlist.isEmpty) return;
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

    // Handle track completion.
    _playerStateSubscription = _player!.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          !_isSkipping &&
          !_isLoading) {
        _handleCompletion();
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

  /// Handle track completion with proper repeat/advance logic.
  Future<void> _handleCompletion() async {
    final isLastTrack = _currentIndex >= _playlist.length - 1;
    try {
      if (_repeatMode == RepeatMode.one) {
        await _player!.seek(Duration.zero);
        _player!.play();
      } else if (_repeatMode == RepeatMode.all &&
          _playlist.isNotEmpty &&
          isLastTrack) {
        _currentIndex = 0;
        _currentTrack = _playlist[0];
        if (_audioHandler != null) {
          _audioHandler!.updateTrackInfo(_currentTrack!);
        }
        notifyListeners();
        await _player!.seek(Duration.zero, index: 0);
        _player!.play();
      }
    } catch (e) {
      debugPrint('Error handling playlist completion: $e');
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
    _originalPlaylist = [track];
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

  /// Play a playlist. Pass [startIndex] = -1 with shuffle enabled to start
  /// from a random track.
  Future<void> playPlaylist(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    if (startIndex != -1 && (startIndex < 0 || startIndex >= tracks.length)) {
      return;
    }

    _ensurePlayerInitialized();
    _lastError = null;
    final token = ++_loadToken;

    _isLoading = true;
    _originalPlaylist = List.from(tracks);
    _playlist = List.from(tracks);

    if (_isShuffleEnabled) {
      _shufflePlaylist(startIndex);
    } else {
      _currentIndex = startIndex < 0 ? 0 : startIndex;
    }

    _currentTrack = _playlist[_currentIndex];
    notifyListeners();

    try {
      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(_currentTrack!);
      }

      final source = _buildPlaylistSource(_playlist);
      await _setSourceAndPlay(source, initialIndex: _currentIndex);

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

  /// Play next track in playlist.
  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    _ensurePlayerInitialized();
    _lastError = null;

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
    await _skipToIndex(_currentIndex);
  }

  /// Play previous track in playlist.
  Future<void> playPrevious() async {
    if (_playlist.isEmpty || _currentIndex <= 0) return;
    _ensurePlayerInitialized();
    _lastError = null;
    _currentIndex--;

    _currentTrack = _playlist[_currentIndex];
    notifyListeners();
    await _skipToIndex(_currentIndex);
  }

  /// Internal: skip to a specific index in the ConcatenatingAudioSource.
  Future<void> _skipToIndex(int index) async {
    final token = ++_skipToken;
    _isLoading = true;
    _isSkipping = true;

    try {
      if (_audioHandler != null && _currentTrack != null) {
        _audioHandler!.updateTrackInfo(_currentTrack!);
      }

      if (_player?.audioSource == null) return;

      await _player!.seek(Duration.zero, index: index);
      if (token != _skipToken) return;
      if (!_player!.playing) {
        _player!.play();
      }
      if (token == _skipToken) {
        _updateWindowsMetadata(_currentTrack);
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

  /// Toggle shuffle mode.
  Future<void> toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_playlist.isNotEmpty && _currentTrack != null && _player != null) {
      final wasPlaying = _player!.playing;
      final currentPosition = _player!.position;

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

      try {
        final source = _buildPlaylistSource(_playlist);
        await _player!.setAudioSource(source, initialIndex: _currentIndex);
        await _player!.seek(currentPosition);
        if (wasPlaying) {
          _player!.play();
        }
      } catch (e) {
        debugPrint('Error rebuilding playlist after shuffle toggle: $e');
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

  /// Shuffle the playlist. If [startIndex] is -1, pick a random track.
  void _shufflePlaylist(int startIndex) {
    if (_playlist.isEmpty) return;

    if (startIndex < 0 || startIndex >= _playlist.length) {
      _playlist.shuffle(_random);
    } else {
      final firstTrack = _playlist[startIndex];
      _playlist.removeAt(startIndex);
      _playlist.shuffle(_random);
      _playlist.insert(0, firstTrack);
    }
    _currentIndex = 0;
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
