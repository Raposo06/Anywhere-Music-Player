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

  group('RotatingStreamUrlResolver', () {
    test('throws when nothing has been bound yet (not logged in)', () {
      final rotating = RotatingStreamUrlResolver();
      expect(() => rotating.buildStreamUrl('1'), throwsStateError);
      expect(() => rotating.buildCoverArtUrl('1'), throwsStateError);
    });

    test('delegates to whatever it was last updated with', () {
      final rotating = RotatingStreamUrlResolver();
      rotating.updateFrom(resolver);

      expect(rotating.buildStreamUrl('1'), resolver.buildStreamUrl('1'));
    });

    test('reverts to throwing after updateFrom(null) — e.g. on logout', () {
      final rotating = RotatingStreamUrlResolver();
      rotating.updateFrom(resolver);
      rotating.updateFrom(null);

      expect(() => rotating.buildStreamUrl('1'), throwsStateError);
    });

    test('picks up a new session after updateFrom is called again — e.g. re-login', () {
      final rotating = RotatingStreamUrlResolver();
      rotating.updateFrom(resolver);
      const otherResolver = FakeStreamUrlResolver();
      rotating.updateFrom(otherResolver);

      expect(rotating.buildStreamUrl('1'), otherResolver.buildStreamUrl('1'));
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
