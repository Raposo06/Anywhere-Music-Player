import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

/// Transport-control callbacks a presence adapter routes system button
/// presses (SMTC, notification, car head unit) back into. `stop` is included
/// for completeness even though today only [WindowsPresence] wires it —
/// audio_service's Android handler stops the player directly.
typedef PlaybackCommands = ({
  void Function() play,
  void Function() pause,
  void Function() next,
  void Function() previous,
  void Function() stop,
});

/// Tells the OS what's playing and exposes system-level transport controls
/// for it — the SMTC/taskbar/window-title/wakelock quartet on Windows, the
/// notification/lock-screen/car-head-unit handler on Android. Two adapters
/// already existed, interleaved inline in [AudioPlayerService] behind
/// `if (_isWindows)` and `if (_audioHandler != null)` branches; this is the
/// seam that removes them. See
/// docs/reviews/2026-08-22-architecture-review.html Candidate 06.
abstract class NowPlayingPresence {
  /// Wire transport-control callbacks (and, for adapters that need the live
  /// player to broadcast state — Android's audio_service handler does) the
  /// player itself. Called once, right after the player is created.
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

/// No-op adapter — the default. Used on any platform without a presence
/// need of its own (iOS/macOS/Linux/web today) and in tests, so tests never
/// depend on a real Windows or Android platform channel.
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
