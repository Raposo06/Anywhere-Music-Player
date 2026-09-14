/// Reports listening back to the server, so the server's own statistics —
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
/// play count is not a failure worth propagating, so this stays silent. In
/// production the reporter is `AuthService`, which follows the session and
/// drops reports the same way while logged out.
class NoPlaybackReporter implements PlaybackReporter {
  const NoPlaybackReporter();

  @override
  Future<void> nowPlaying(String songId) async {}

  @override
  Future<void> scrobble(String songId, {DateTime? startedAt}) async {}
}
