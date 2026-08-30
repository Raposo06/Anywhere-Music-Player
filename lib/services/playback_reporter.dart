/// Reports listening back to the server, so Navidrome's own statistics —
/// play counts, "recently played", "most played", and any Last.fm /
/// ListenBrainz bridge configured on the server side — reflect what this app
/// actually played.
///
/// A seam for the same reason [StreamUrlResolver] and [NowPlayingPresence]
/// are: [AudioPlayerService] shouldn't know about the transport, and tests
/// shouldn't need one. Implemented by [SubsonicApiService] over
/// `/rest/scrobble`.
///
/// Both methods are **best-effort telemetry**. Implementations may throw;
/// callers are expected to swallow it. Nothing here is worth interrupting
/// playback for.
abstract class PlaybackReporter {
  /// Announce that [songId] has started — Subsonic's `submission=false`.
  /// Drives the server's "now playing" panel; it is not a play count.
  Future<void> nowPlaying(String songId);

  /// Record a completed listen of [songId] — Subsonic's `submission=true`.
  /// This is the one that increments the play count.
  ///
  /// [startedAt] is when the listen *began*, not when the threshold was
  /// crossed, so the server times the play correctly rather than logging it
  /// minutes late.
  Future<void> scrobble(String songId, {DateTime? startedAt});
}

/// The default, and the one tests get: reports nowhere.
///
/// Unlike [NoResolver] — where a missing resolver means playback genuinely
/// cannot proceed, so it throws — a missing reporter is harmless. Losing a
/// play count is not a failure worth propagating, so this stays silent.
class NoPlaybackReporter implements PlaybackReporter {
  const NoPlaybackReporter();

  @override
  Future<void> nowPlaying(String songId) async {}

  @override
  Future<void> scrobble(String songId, {DateTime? startedAt}) async {}
}

/// A stable reporter reference that [AudioPlayerService] can be constructed
/// with once, before login, and that keeps working across logout/re-login —
/// exactly like [RotatingStreamUrlResolver], and wired the same way from
/// `main.dart` whenever [AuthService] changes.
///
/// Reports while logged out are dropped rather than thrown: "no session" is a
/// normal state for telemetry to be in, not an error.
class RotatingPlaybackReporter implements PlaybackReporter {
  PlaybackReporter? _current;

  void updateFrom(PlaybackReporter? reporter) {
    _current = reporter;
  }

  @override
  Future<void> nowPlaying(String songId) async => _current?.nowPlaying(songId);

  @override
  Future<void> scrobble(String songId, {DateTime? startedAt}) async =>
      _current?.scrobble(songId, startedAt: startedAt);
}
