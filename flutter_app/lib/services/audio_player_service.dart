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
  bool _isShuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.off;
  double _volume = 1.0; // 0.0 to 1.0
  String? _lastError;
  final _random = Random();

  /// Streams exposed for UI widgets that need high-frequency updates (e.g., progress bar).
  /// Using streams instead of notifyListeners() avoids rebuilding the entire widget tree.
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
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
  Duration? get position => _player.position;
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
    _player.playingStream.listen((playing) {
      if (_isWindows) {
        _windowsMediaControls.updatePlaybackStatus(isPlaying: playing);
      }
      notifyListeners();
    });

    // Auto-play next track when current finishes
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_repeatMode == RepeatMode.one) {
          _player.seek(Duration.zero);
          _player.play();
        } else {
          playNext();
        }
      }
    });

    // Listen for playback errors
    _player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        _handlePlaybackError(e);
      },
    );
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

  /// Play a single track
  Future<void> playTrack(Track track) async {
    _lastError = null;

    try {
      _isLoading = true;
      _currentTrack = track;
      _playlist = [track];
      _currentIndex = 0;
      notifyListeners();

      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(track);
      }

      final source = _buildPlaylistSource([track]);
      await _player.setAudioSource(source);
      await _player.play();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _handlePlaybackError(e);
      rethrow;
    }
  }

  /// Set a playlist and play from a specific index using ConcatenatingAudioSource
  /// for gapless playback.
  Future<void> playPlaylist(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) {
      return;
    }

    _lastError = null;

    try {
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

      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(_currentTrack!);
      }

      final source = _buildPlaylistSource(_playlist);
      await _player.setAudioSource(source, initialIndex: _currentIndex);
      await _player.play();

      // Listen for track changes within the concatenating source
      _player.currentIndexStream.listen((index) {
        if (index != null && index != _currentIndex && index < _playlist.length) {
          _currentIndex = index;
          _currentTrack = _playlist[_currentIndex];
          if (_audioHandler != null) {
            _audioHandler!.updateTrackInfo(_currentTrack!);
          }
          notifyListeners();
        }
      });

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _handlePlaybackError(e);
      rethrow;
    }
  }

  /// Play next track in playlist
  Future<void> playNext() async {
    if (_playlist.isEmpty) return;

    _lastError = null;

    if (_currentIndex >= _playlist.length - 1) {
      if (_repeatMode == RepeatMode.all) {
        _currentIndex = 0;
      } else {
        stop();
        return;
      }
    } else {
      _currentIndex++;
    }

    _currentTrack = _playlist[_currentIndex];
    _isLoading = true;
    notifyListeners();

    try {
      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(_currentTrack!);
      }
      await _player.seek(Duration.zero, index: _currentIndex);
      if (!_player.playing) {
        await _player.play();
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      if (!e.toString().contains('Loading interrupted')) {
        _handlePlaybackError(e);
      }
      notifyListeners();
    }
  }

  /// Play previous track in playlist
  Future<void> playPrevious() async {
    if (_playlist.isEmpty || _currentIndex <= 0) return;

    _lastError = null;
    _currentIndex--;
    _currentTrack = _playlist[_currentIndex];
    _isLoading = true;
    notifyListeners();

    try {
      if (_audioHandler != null) {
        _audioHandler!.updateTrackInfo(_currentTrack!);
      }
      await _player.seek(Duration.zero, index: _currentIndex);
      if (!_player.playing) {
        await _player.play();
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      if (!e.toString().contains('Loading interrupted')) {
        _handlePlaybackError(e);
      }
      notifyListeners();
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

  /// Seek to a specific position
  Future<void> seek(Duration position) async {
    final currentPos = _player.position;
    final seekDistance = (position - currentPos).abs();

    if (seekDistance.inSeconds > 30) {
      _isSeeking = true;
      notifyListeners();
    }

    try {
      await _player.seek(position);
    } finally {
      if (_isSeeking) {
        _isSeeking = false;
        notifyListeners();
      }
    }
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

  /// Toggle shuffle mode
  void toggleShuffle() {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_playlist.isNotEmpty) {
      if (_isShuffleEnabled) {
        final currentTrack = _currentTrack;
        if (currentTrack != null) {
          final currentTrackIndex = _playlist.indexOf(currentTrack);
          if (currentTrackIndex >= 0) {
            _shufflePlaylist(currentTrackIndex);
          }
        }
      } else {
        if (_originalPlaylist.isNotEmpty) {
          final currentTrack = _currentTrack;
          _playlist = List.from(_originalPlaylist);
          if (currentTrack != null) {
            final index = _playlist.indexWhere((t) => t.id == currentTrack.id);
            if (index >= 0) {
              _currentIndex = index;
            }
          }
        }
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
    _player.dispose();
    if (_isWindows) {
      _windowsMediaControls.dispose();
    }
    super.dispose();
  }
}
