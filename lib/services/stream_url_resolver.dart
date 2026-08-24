import '../models/cover_art_ref.dart';

/// Mints stream and cover-art URLs on demand. Implemented by
/// [SubsonicApiService] (see its `buildStreamUrl`/`buildCoverArtUrl`, which
/// this interface mirrors exactly). [Track] and [Folder] used to hold a
/// pre-signed URL of each kind, minted once at scan/parse time and frozen in
/// memory for the rest of the session — meaning every track held a live,
/// password-equivalent auth token+salt for as long as it stayed loaded, and
/// the model had to import the transport just to mint it. Consulting a
/// resolver at the moment of use (playback, or a cover render) instead
/// reverses that dependency and mints a fresh URL each time — which is what
/// the auth scheme already assumes (see the Android stream-cache decision:
/// keyed on track id because the salt rotates on every request).
///
/// See docs/reviews/2026-08-22-architecture-review.html Candidate 07, and
/// docs/decisions.md "Cached cover art stores the id, not the resolved URL"
/// — this extends that reasoning to the in-memory copy. Nothing about the
/// security floor changes: the id is still the only thing ever persisted.
abstract class StreamUrlResolver {
  String buildStreamUrl(String songId);
  String buildCoverArtUrl(String coverArtId, {int? size});
}

/// Null-safe helpers for the common "resolve if I can" shape every
/// consultation site needs — a possibly-absent resolver (logged out) and a
/// possibly-absent [CoverArtRef.coverArtId] (no cover) both mean "no URL",
/// not an error.
extension ResolveOrNull on StreamUrlResolver? {
  String? resolveStreamUrl(String trackId) => this?.buildStreamUrl(trackId);

  String? resolveCoverUrl(CoverArtRef source, {int? size}) {
    final id = source.coverArtId;
    final resolver = this;
    if (resolver == null || id == null) return null;
    return resolver.buildCoverArtUrl(id, size: size);
  }
}

/// The default when no resolver is configured. Unlike [NowPlayingPresence]'s
/// no-op default, there's no safe no-op here — a missing resolver means
/// playback genuinely cannot proceed, so this fails loudly and immediately
/// rather than silently building a broken URL.
class NoResolver implements StreamUrlResolver {
  const NoResolver();
  @override
  String buildStreamUrl(String songId) =>
      throw StateError('No StreamUrlResolver configured — not logged in?');
  @override
  String buildCoverArtUrl(String coverArtId, {int? size}) =>
      throw StateError('No StreamUrlResolver configured — not logged in?');
}

/// A stable resolver reference that [AudioPlayerService] can be constructed
/// with once, before login, and that keeps working across logout/re-login —
/// unlike [AuthService.apiService] itself, which is a whole new instance
/// each session. `main.dart` mutates this in place whenever [AuthService]
/// changes; nothing else needs to know that's happening.
class RotatingStreamUrlResolver implements StreamUrlResolver {
  StreamUrlResolver? _current;

  void updateFrom(StreamUrlResolver? resolver) {
    _current = resolver;
  }

  @override
  String buildStreamUrl(String songId) {
    final resolver = _current;
    if (resolver == null) {
      throw StateError('No StreamUrlResolver bound — not logged in?');
    }
    return resolver.buildStreamUrl(songId);
  }

  @override
  String buildCoverArtUrl(String coverArtId, {int? size}) {
    final resolver = _current;
    if (resolver == null) {
      throw StateError('No StreamUrlResolver bound — not logged in?');
    }
    return resolver.buildCoverArtUrl(coverArtId, size: size);
  }
}
