import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

class AudioPlayerService with ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  Track? _currentTrack;
  List<Track> _playlist = [];
  List<Track> _originalPlaylist = [];
  int _currentIndex = -1;
  bool _isLoading = false;
  bool _isShuffleEnabled = false;
  String? _lastError;
  final _random = Random();

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentTrack;
  List<Track> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  bool get isShuffleEnabled => _isShuffleEnabled;
  String? get lastError => _lastError;

  bool get isPlaying => _player.playing;
  Duration? get duration => _player.duration;
  Duration? get position => _player.position;

  /// Check if we're running on Windows
  bool get _isWindows => !kIsWeb && Platform.isWindows;

  AudioPlayerService() {
    // Listen to player state changes
    _player.playingStream.listen((_) {
      notifyListeners();
    });

    _player.positionStream.listen((_) {
      notifyListeners();
    });

    _player.durationStream.listen((_) {
      notifyListeners();
    });

    // Auto-play next track when current finishes
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        playNext();
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

      // Stop and clear previous track
      await _player.stop();

      debugPrint('🎵 Playing: ${track.title}');
      debugPrint('📡 Stream URL: ${track.streamUrl}');

      await _player.setUrl(track.streamUrl);
      await _player.play();

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

      // Stop and clear previous track
      await _player.stop();

      // Debug: Print the stream URL being attempted
      debugPrint('🎵 Playing: ${_currentTrack!.title}');
      debugPrint('📡 Stream URL: ${_playlist[_currentIndex].streamUrl}');

      await _player.setUrl(_playlist[_currentIndex].streamUrl);
      await _player.play();

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
    if (_playlist.isEmpty || _currentIndex >= _playlist.length - 1) {
      return;
    }

    if (_isLoading) return; // Prevent multiple simultaneous loads

    // Clear any previous error
    _lastError = null;

    _currentIndex++;
    _currentTrack = _playlist[_currentIndex];
    _isLoading = true;
    notifyListeners();

    try {
      // Debug: Print the stream URL being attempted
      debugPrint('🎵 Next: ${_currentTrack!.title}');
      debugPrint('📡 Stream URL: ${_currentTrack!.streamUrl}');

      // Stop previous track
      await _player.stop();

      // Set new URL and play - await both to ensure proper sequencing
      await _player.setUrl(_currentTrack!.streamUrl);

      // Explicitly call play and wait for it to start
      await _player.play();

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

      // Stop previous track
      await _player.stop();

      // Set new URL and play - await both to ensure proper sequencing
      await _player.setUrl(_currentTrack!.streamUrl);

      // Explicitly call play and wait for it to start
      await _player.play();

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
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Stop playback and clear current track
  Future<void> stop() async {
    await _player.stop();
    _currentTrack = null;
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
    super.dispose();
  }
}
