import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/track.dart';
import 'audio_handler.dart';
// import 'windows_media_controls_service.dart';  // REMOVED: smtc_windows package removed
import 'api_service.dart';

enum RepeatMode { off, all, one }

class AudioPlayerService with ChangeNotifier {
  late final AudioPlayer _player;
  final ApiService _apiService;
  MusicAudioHandler? _audioHandler;
  // final WindowsMediaControlsService _windowsMediaControls = WindowsMediaControlsService.instance;  // REMOVED
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

  AudioPlayerService(this._apiService) {
    // Initialize audio player
    _player = AudioPlayer();

    // Initialize audio handler for system media controls
    _initializeAudioHandler();

    // DISABLED: Windows SMTC causes keyboard control issues
    // Will re-enable after confirming just_audio_windows fix works
    // _initializeWindowsMediaControls();

    // Listen to player state changes
    _player.playingStream.listen((playing) {
      debugPrint('🎵 Player state changed: ${playing ? "Playing" : "Paused/Stopped"}');
      // DISABLED: updatePlaybackStatus call removed to prevent any SMTC interaction
      // _windowsMediaControls.updatePlaybackStatus(isPlaying: playing);
      notifyListeners();
    });

    _player.positionStream.listen((_) {
      notifyListeners();
    });

    _player.durationStream.listen((_) {
      notifyListeners();
    });

    _player.bufferedPositionStream.listen((_) {
      notifyListeners();
    });

    // Auto-play next track when current finishes
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_repeatMode == RepeatMode.one) {
          // Replay current track
          _player.seek(Duration.zero);
          _player.play();
        } else {
          // Advance to next track
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

  /// Initialize the audio handler for system media controls
  Future<void> _initializeAudioHandler() async {
    try {
      _audioHandler = await AudioService.init(
        builder: () => MusicAudioHandler(
          player: _player,
          onNext: playNext,
          onPrevious: playPrevious,
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.anywhere_music_player.audio',
          androidNotificationChannelName: 'Music Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      ) as MusicAudioHandler;
    } catch (e) {
      debugPrint('⚠️ Audio service not available: $e');
      // Audio service may not be available on web or in some environments
    }
  }

  // REMOVED: Windows media controls methods (smtc_windows package removed)
  // _initializeWindowsMediaControls() - no longer needed
  // _updateWindowsMediaControls() - no longer needed

  /// Handle playback errors with platform-specific messages
  void _handlePlaybackError(Object error) {
    final errorStr = error.toString();

    if (_isWindows && errorStr.contains('Media error')) {
      _lastError = 'Windows playback error. The audio format may not be supported.';
      debugPrint('🔴 Windows Media Error: $errorStr');
      debugPrint('💡 Tip: Ensure the audio file is a valid MP3 and the server returns proper Content-Length headers.');
    } else {
      _lastError = 'Playback error: $errorStr';
      debugPrint('🔴 Playback error: $errorStr');
    }

    notifyListeners();
  }

  /// Clear the last error
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Play a single track
  Future<void> playTrack(Track track) async {
    if (_isLoading) return; // Prevent multiple simultaneous loads

    // Clear any previous error
    _lastError = null;

    try {
      _isLoading = true;
      _currentTrack = track;
      _playlist = [track];
      _currentIndex = 0;
      notifyListeners();

      debugPrint('🎵 Playing: ${track.title}');
      debugPrint('📡 Stream URL: ${track.streamUrl}');

      // Create AudioSource with authentication headers
      // This fixes the auto-pause issue caused by 401/403 errors
      final source = AudioSource.uri(
        Uri.parse(track.streamUrl),
        headers: _apiService.getHeaders(authenticated: true),
        tag: MediaItem(
          id: track.id,
          title: track.title,
          artist: track.folderPath.isNotEmpty ? track.folderPath : 'Unknown Artist',
          duration: track.durationSeconds != null
              ? Duration(seconds: track.durationSeconds!)
              : null,
          artUri: track.coverArtUrl != null ? Uri.parse(track.coverArtUrl!) : null,
        ),
      );

      // Use setAudioSource instead of setUrl for proper state management
      await _player.setAudioSource(source);
      await _player.play();

      // Update system media controls with track info
      _audioHandler?.updateTrackInfo(track);
      // DISABLED: Windows media controls still have keyboard issues
      // _updateWindowsMediaControls();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _handlePlaybackError(e);
      debugPrint('Error playing track: $e');
      rethrow;
    }
  }

  /// Set a playlist and play from a specific index
  Future<void> playPlaylist(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) {
      return;
    }

    if (_isLoading) return; // Prevent multiple simultaneous loads

    // Clear any previous error
    _lastError = null;

    try {
      _isLoading = true;
      _originalPlaylist = List.from(tracks);
      _playlist = List.from(tracks);

      // Apply shuffle if enabled
      if (_isShuffleEnabled) {
        _shufflePlaylist(startIndex);
      } else {
        _currentIndex = startIndex;
      }

      _currentTrack = _playlist[_currentIndex];
      notifyListeners();

      // Debug: Print the stream URL being attempted
      debugPrint('🎵 Playing: ${_currentTrack!.title}');
      debugPrint('📡 Stream URL: ${_playlist[_currentIndex].streamUrl}');

      // Create AudioSource with authentication headers
      final source = AudioSource.uri(
        Uri.parse(_playlist[_currentIndex].streamUrl),
        headers: _apiService.getHeaders(authenticated: true),
        tag: MediaItem(
          id: _currentTrack!.id,
          title: _currentTrack!.title,
          artist: _currentTrack!.folderPath.isNotEmpty ? _currentTrack!.folderPath : 'Unknown Artist',
          duration: _currentTrack!.durationSeconds != null
              ? Duration(seconds: _currentTrack!.durationSeconds!)
              : null,
          artUri: _currentTrack!.coverArtUrl != null ? Uri.parse(_currentTrack!.coverArtUrl!) : null,
        ),
      );

      // Use setAudioSource for proper state management
      await _player.setAudioSource(source);
      await _player.play();

      // Update system media controls with track info
      _audioHandler?.updateTrackInfo(_currentTrack!);
      // DISABLED: Windows media controls still have keyboard issues
      // _updateWindowsMediaControls();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _handlePlaybackError(e);
      debugPrint('Error playing playlist: $e');
      rethrow;
    }
  }

  /// Play next track in playlist
  Future<void> playNext() async {
    if (_playlist.isEmpty) {
      return;
    }

    if (_isLoading) return; // Prevent multiple simultaneous loads

    // Clear any previous error
    _lastError = null;

    // Handle end of playlist
    if (_currentIndex >= _playlist.length - 1) {
      if (_repeatMode == RepeatMode.all) {
        // Loop back to first track
        _currentIndex = 0;
      } else {
        // Stop playback
        stop();
        return;
      }
    } else {
      // Normal next track
      _currentIndex++;
    }

    _currentTrack = _playlist[_currentIndex];
    _isLoading = true;
    notifyListeners();

    try {
      // Debug: Print the stream URL being attempted
      debugPrint('🎵 Next: ${_currentTrack!.title}');
      debugPrint('📡 Stream URL: ${_currentTrack!.streamUrl}');

      // Create AudioSource with authentication headers
      final source = AudioSource.uri(
        Uri.parse(_currentTrack!.streamUrl),
        headers: _apiService.getHeaders(authenticated: true),
        tag: MediaItem(
          id: _currentTrack!.id,
          title: _currentTrack!.title,
          artist: _currentTrack!.folderPath.isNotEmpty ? _currentTrack!.folderPath : 'Unknown Artist',
          duration: _currentTrack!.durationSeconds != null
              ? Duration(seconds: _currentTrack!.durationSeconds!)
              : null,
          artUri: _currentTrack!.coverArtUrl != null ? Uri.parse(_currentTrack!.coverArtUrl!) : null,
        ),
      );

      // Use setAudioSource for proper state management
      await _player.setAudioSource(source);
      await _player.play();

      // Update system media controls with track info
      _audioHandler?.updateTrackInfo(_currentTrack!);
      // DISABLED: Windows media controls still have keyboard issues
      // _updateWindowsMediaControls();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      // Don't print "Loading interrupted" - it's expected when switching tracks quickly
      if (!e.toString().contains('Loading interrupted')) {
        _handlePlaybackError(e);
        debugPrint('Error playing next track: $e');
      }
      notifyListeners();
    }
  }

  /// Play previous track in playlist
  Future<void> playPrevious() async {
    if (_playlist.isEmpty || _currentIndex <= 0) {
      return;
    }

    if (_isLoading) return; // Prevent multiple simultaneous loads

    // Clear any previous error
    _lastError = null;

    _currentIndex--;
    _currentTrack = _playlist[_currentIndex];
    _isLoading = true;
    notifyListeners();

    try {
      // Debug: Print the stream URL being attempted
      debugPrint('🎵 Previous: ${_currentTrack!.title}');
      debugPrint('📡 Stream URL: ${_currentTrack!.streamUrl}');

      // Create AudioSource with authentication headers
      final source = AudioSource.uri(
        Uri.parse(_currentTrack!.streamUrl),
        headers: _apiService.getHeaders(authenticated: true),
        tag: MediaItem(
          id: _currentTrack!.id,
          title: _currentTrack!.title,
          artist: _currentTrack!.folderPath.isNotEmpty ? _currentTrack!.folderPath : 'Unknown Artist',
          duration: _currentTrack!.durationSeconds != null
              ? Duration(seconds: _currentTrack!.durationSeconds!)
              : null,
          artUri: _currentTrack!.coverArtUrl != null ? Uri.parse(_currentTrack!.coverArtUrl!) : null,
        ),
      );

      // Use setAudioSource for proper state management
      await _player.setAudioSource(source);
      await _player.play();

      // Update system media controls with track info
      _audioHandler?.updateTrackInfo(_currentTrack!);
      // DISABLED: Windows media controls still have keyboard issues
      // _updateWindowsMediaControls();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      // Don't print "Loading interrupted" - it's expected when switching tracks quickly
      if (!e.toString().contains('Loading interrupted')) {
        _handlePlaybackError(e);
        debugPrint('Error playing previous track: $e');
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
    notifyListeners();
  }

  /// Seek to a specific position
  /// Shows loading state for large seeks to give user feedback
  Future<void> seek(Duration position) async {
    final currentPos = _player.position;
    final seekDistance = (position - currentPos).abs();

    // For seeks > 30 seconds, show loading indicator
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
    // _windowsMediaControls.clear();  // REMOVED: SMTC disabled
    notifyListeners();
  }

  /// Toggle shuffle mode
  void toggleShuffle() {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_playlist.isNotEmpty) {
      if (_isShuffleEnabled) {
        // Shuffle the playlist, keeping current track at index 0
        final currentTrack = _currentTrack;
        if (currentTrack != null) {
          final currentTrackIndex = _playlist.indexOf(currentTrack);
          if (currentTrackIndex >= 0) {
            _shufflePlaylist(currentTrackIndex);
          }
        }
      } else {
        // Restore original order
        if (_originalPlaylist.isNotEmpty) {
          final currentTrack = _currentTrack;
          _playlist = List.from(_originalPlaylist);

          // Find current track in original playlist
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

    // Get the track that should be first
    final firstTrack = _playlist[startIndex];

    // Remove it from the list
    _playlist.removeAt(startIndex);

    // Shuffle the remaining tracks
    _playlist.shuffle(_random);

    // Insert the first track at the beginning
    _playlist.insert(0, firstTrack);

    // Set current index to 0
    _currentIndex = 0;
  }

  @override
  void dispose() {
    _player.dispose();
    // DISABLED: Windows media controls not initialized
    // _windowsMediaControls.dispose();
    super.dispose();
  }
}
