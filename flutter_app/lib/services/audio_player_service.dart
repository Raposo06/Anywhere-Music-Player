import 'dart:math';
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
  final _random = Random();

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentTrack;
  List<Track> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  bool get isShuffleEnabled => _isShuffleEnabled;

  bool get isPlaying => _player.playing;
  Duration? get duration => _player.duration;
  Duration? get position => _player.position;

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
  }

  /// Play a single track
  Future<void> playTrack(Track track) async {
    if (_isLoading) return; // Prevent multiple simultaneous loads

    try {
      _isLoading = true;
      _currentTrack = track;
      _playlist = [track];
      _currentIndex = 0;
      notifyListeners();

      // Stop and clear previous track
      await _player.stop();

      await _player.setUrl(track.streamUrl);
      await _player.play();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
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

      await _player.setUrl(_playlist[_currentIndex].streamUrl);
      await _player.play();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
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

    _currentIndex++;
    _currentTrack = _playlist[_currentIndex];

    try {
      _isLoading = true;
      notifyListeners();

      // Stop and clear previous track
      await _player.stop();

      await _player.setUrl(_currentTrack!.streamUrl);
      await _player.play();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      // Don't print "Loading interrupted" - it's expected when switching tracks quickly
      if (!e.toString().contains('Loading interrupted')) {
        debugPrint('Error playing next track: $e');
      }
    }
  }

  /// Play previous track in playlist
  Future<void> playPrevious() async {
    if (_playlist.isEmpty || _currentIndex <= 0) {
      return;
    }

    if (_isLoading) return; // Prevent multiple simultaneous loads

    _currentIndex--;
    _currentTrack = _playlist[_currentIndex];

    try {
      _isLoading = true;
      notifyListeners();

      // Stop and clear previous track
      await _player.stop();

      await _player.setUrl(_currentTrack!.streamUrl);
      await _player.play();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      // Don't print "Loading interrupted" - it's expected when switching tracks quickly
      if (!e.toString().contains('Loading interrupted')) {
        debugPrint('Error playing previous track: $e');
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
