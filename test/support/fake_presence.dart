import 'package:just_audio/just_audio.dart';
import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/services/now_playing_presence.dart';

/// Records every call instead of reaching a real Windows/Android platform
/// channel — lets a test assert "starting a track shows it to the OS"
/// directly. See docs/reviews/2026-08-22-architecture-review.html
/// Candidate 06 — this is the "recording fake" it describes replacing the
/// window_manager MethodChannel mock with.
class RecordingPresence implements NowPlayingPresence {
  final List<Track> shown = [];
  final List<bool> playingStates = [];
  int clearCount = 0;
  int disposeCount = 0;
  AudioPlayer? boundPlayer;
  PlaybackCommands? boundCommands;

  @override
  void bind(AudioPlayer player, PlaybackCommands commands) {
    boundPlayer = player;
    boundCommands = commands;
  }

  @override
  void show(Track track) => shown.add(track);

  @override
  void setPlaying(bool playing) => playingStates.add(playing);

  @override
  void clear() => clearCount++;

  @override
  void dispose() => disposeCount++;
}
