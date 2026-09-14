import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/services/stream_url_resolver.dart';
import '../support/fake_resolver.dart';
import '../support/fixtures.dart';

// Covers the seam Candidate 07 introduces: Track/Folder stopped carrying a
// pre-signed streamUrl/coverArtUrl, so this is now the one place "what's the
// URL for this id" logic lives. See
// docs/reviews/2026-08-22-architecture-review.html Candidate 07.
void main() {
  const resolver = FakeStreamUrlResolver();

  group('ResolveOrNull.resolveStreamUrl', () {
    test('delegates to the resolver', () {
      expect(resolver.resolveStreamUrl('42'), resolver.buildStreamUrl('42'));
    });

    test('returns null when there is no resolver (logged out)', () {
      const StreamUrlResolver? none = null;
      expect(none.resolveStreamUrl('42'), isNull);
    });
  });

  group('ResolveOrNull.resolveCoverUrl', () {
    test('resolves when both a resolver and a coverArtId are present', () {
      final track = sampleTrack(coverArtId: 'cov-1');
      expect(resolver.resolveCoverUrl(track), resolver.buildCoverArtUrl('cov-1'));
      expect(
        resolver.resolveCoverUrl(track, size: 300),
        resolver.buildCoverArtUrl('cov-1', size: 300),
      );
    });

    test('returns null when there is no cover art id, even with a resolver', () {
      final track = sampleTrack(); // no coverArtId
      expect(resolver.resolveCoverUrl(track), isNull);
    });

    test('returns null when there is no resolver, even with a cover art id', () {
      const StreamUrlResolver? none = null;
      final track = sampleTrack(coverArtId: 'cov-1');
      expect(none.resolveCoverUrl(track), isNull);
    });
  });

  group('NoResolver', () {
    test('throws on every call — the safe default when nothing is configured', () {
      const none = NoResolver();
      expect(() => none.buildStreamUrl('1'), throwsStateError);
      expect(() => none.buildCoverArtUrl('1'), throwsStateError);
    });
  });
}
