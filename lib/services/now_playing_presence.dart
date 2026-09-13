import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

/// Transport-control callbacks a presence adapter routes system button
/// presses (SMTC, MPRIS) back into. `stop` is included for completeness even
/// though today only [WindowsPresence] wires it.
typedef PlaybackCommands = ({
  void Function() play,
  void Function() pause,
  void Function() next,
  void Function() previous,
  void Function() stop,
});

/// Tells the OS what's playing and exposes system-level transport controls
/// for it — the SMTC/taskbar/window-title/wakelock quartet on Windows, the
/// MPRIS D-Bus interface on Linux. The adapters used to be interleaved inline
/// in [AudioPlayerService] behind platform branches; this is the seam that
/// removed them. See docs/reviews/2026-08-22-architecture-review.html
/// Candidate 06.
abstract class NowPlayingPresence {
  /// Wire transport-control callbacks, and the live player for adapters that
  /// need it to broadcast state. Called once, right after the player is
  /// created.
  void bind(AudioPlayer player, PlaybackCommands commands);

  /// Show [track] as now playing.
  void show(Track track);

  /// Report the current playing/paused state. Only called while a track is
  /// current — callers don't need to guard against "nothing loaded yet".
  void setPlaying(bool playing);

  /// Nothing is playing anymore.
  void clear();

  /// Release any held resources (wakelock, native handles).
  void dispose();
}

/// No-op adapter — the default, and what tests get, so tests never depend on
/// a real Windows or Linux platform channel.
class NoPresence implements NowPlayingPresence {
  const NoPresence();
  @override
  void bind(AudioPlayer player, PlaybackCommands commands) {}
  @override
  void show(Track track) {}
  @override
  void setPlaying(bool playing) {}
  @override
  void clear() {}
  @override
  void dispose() {}
}
