import '../models/track.dart';

/// Transport-control callbacks a presence adapter routes system button
/// presses (SMTC, MPRIS) back into.
typedef PlaybackCommands = ({
  void Function() play,
  void Function() pause,
  void Function() next,
  void Function() previous,
  void Function() stop,
});

/// The two live facts an adapter reads from the player, handed over at
/// [NowPlayingPresence.bind] so the player itself never crosses the seam.
///
/// [playing] is the raw play/pause stream, *ungated* — unlike
/// [NowPlayingPresence.setPlaying], which is only called while a track is
/// current. The Windows wakelock needs the raw one: the PC must never
/// suspend while audio is actually playing, whatever the metadata state.
/// See docs/decisions.md, 2026-08-27. [position] is polled: MPRIS's
/// `Position` property is read on demand, by spec, never pushed.
typedef PlaybackSignals = ({
  Stream<bool> playing,
  Duration Function() position,
});

/// Tells the OS what's playing and exposes system-level transport controls
/// for it — the SMTC/taskbar/window-title/wakelock quartet on Windows, the
/// MPRIS D-Bus interface on Linux. The adapters used to be interleaved inline
/// in [AudioPlayerService] behind platform branches; this is the seam that
/// removed them. See docs/reviews/2026-08-22-architecture-review.html
/// Candidate 06.
///
/// One class per platform implements this directly, OS calls inside. There
/// is no second layer: until 2026-09-14 each adapter forwarded to a
/// `*Service` singleton that re-implemented this same interface minus
/// [bind] — see docs/decisions.md.
abstract class NowPlayingPresence {
  /// Wire transport-control callbacks and the player's live signals. Called
  /// once, right after the player is created.
  void bind(PlaybackCommands commands, PlaybackSignals signals);

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
  void bind(PlaybackCommands commands, PlaybackSignals signals) {}
  @override
  void show(Track track) {}
  @override
  void setPlaying(bool playing) {}
  @override
  void clear() {}
  @override
  void dispose() {}
}
