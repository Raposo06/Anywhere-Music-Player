import 'package:anywhere_music_player/services/stream_url_resolver.dart';

/// A working [StreamUrlResolver] for tests that actually load/play a track
/// (AudioPlayerService's default, [NoResolver], throws — there's no safe
/// no-op for "no URL"). Matches the URL shape sampleTrack() used to hardcode
/// before Track stopped carrying a pre-signed streamUrl/coverArtUrl — see
/// docs/reviews/2026-08-22-architecture-review.html Candidate 07.
class FakeStreamUrlResolver implements StreamUrlResolver {
  const FakeStreamUrlResolver();

  @override
  String buildStreamUrl(String songId) =>
      'https://navidrome.example.com/rest/stream?id=$songId';

  @override
  String buildCoverArtUrl(String coverArtId, {int? size}) =>
      'https://navidrome.example.com/rest/getCoverArt?id=$coverArtId${size != null ? '&size=$size' : ''}';
}
