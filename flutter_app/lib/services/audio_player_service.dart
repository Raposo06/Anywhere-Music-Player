import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

class AudioPlayerService with ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  Track? _currentTrack;
  List<Track> _playlist = [];
  int _currentIndex = -1;

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentTrack;
  List<Track> get playlist => _playlist;
  int get currentIndex => _currentIndex;

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
    try {
      _currentTrack = track;
      _playlist = [track];
      _currentIndex = 0;

      await _player.setUrl(track.streamUrl);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing track: $e');
      rethrow;
    }
  }

  /// Set a playlist and play from a specific index
  Future<void> playPlaylist(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) {
      return;
    }

    try {
      _playlist = tracks;
      _currentIndex = startIndex;
      _currentTrack = tracks[startIndex];

      await _player.setUrl(tracks[startIndex].streamUrl);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing playlist: $e');
      rethrow;
    }
  }

  /// Play next track in playlist
  Future<void> playNext() async {
    if (_playlist.isEmpty || _currentIndex >= _playlist.length - 1) {
      return;
    }

    _currentIndex++;
    _currentTrack = _playlist[_currentIndex];

    try {
      await _player.setUrl(_currentTrack!.streamUrl);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing next track: $e');
    }
  }

  /// Play previous track in playlist
  Future<void> playPrevious() async {
    if (_playlist.isEmpty || _currentIndex <= 0) {
      return;
    }

    _currentIndex--;
    _currentTrack = _playlist[_currentIndex];

    try {
      await _player.setUrl(_currentTrack!.streamUrl);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing previous track: $e');
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

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
