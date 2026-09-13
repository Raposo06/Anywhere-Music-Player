import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/services/now_playing_presence.dart';

/// Records every call instead of reaching a real Windows/Linux platform
/// channel — lets a test assert "starting a track shows it to the OS"
/// directly. See docs/reviews/2026-08-22-architecture-review.html
/// Candidate 06 — this is the "recording fake" it describes replacing the
/// window_manager MethodChannel mock with. Needs nothing from just_audio:
/// the seam hands over signals, not the player.
class RecordingPresence implements NowPlayingPresence {
  final List<Track> shown = [];
  final List<bool> playingStates = [];
  int clearCount = 0;
  int disposeCount = 0;
  PlaybackCommands? boundCommands;
  PlaybackSignals? boundSignals;

  @override
  void bind(PlaybackCommands commands, PlaybackSignals signals) {
    boundCommands = commands;
    boundSignals = signals;
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
