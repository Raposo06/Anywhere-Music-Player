import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/models/folder.dart';
import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/widgets/cover_art.dart';
import '../support/fake_resolver.dart';
import '../support/fixtures.dart';

// CoverArt exists to stop six render sites from independently computing
// size * devicePixelRatio for both the image URL and the cache key — the
// failure mode is a 100% cache miss if the two ever compute it differently,
// not a crash, so it's worth pinning here. See
// docs/reviews/2026-08-22-architecture-review.html Candidate 03.
//
// Uses resolverForTest (CoverArt's test-only seam) instead of a real
// AuthService/Provider tree — see Candidate 07: the URL is resolved live via
// AuthService.apiService in production, but these tests only care that
// CoverArt asks correctly, not that a full logged-in session exists.
//
// These tests read the built CachedNetworkImage's constructor properties
// after a single pump() rather than pumpAndSettle() — this repo has no
// network-image test harness (fixtures.dart deliberately defaults to no
// cover art so widget tests never depend on a real fetch), so we never let
// the actual network attempt resolve; we only assert on what CoverArt built.
void main() {
  const resolver = FakeStreamUrlResolver();
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('no cover art', () {
    testWidgets('shows the fallback icon, not an image', (tester) async {
      await tester.pumpWidget(wrap(
        CoverArt(sampleTrack(), size: 48, resolverForTest: resolver),
      ));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('uses the given fallback icon, color and size', (tester) async {
      await tester.pumpWidget(wrap(CoverArt(
        Folder(folderPath: 'A', trackCount: 0),
        size: 48,
        fallbackIcon: Icons.folder,
        fallbackIconColor: Colors.blue,
        resolverForTest: resolver,
      )));

      final icon = tester.widget<Icon>(find.byIcon(Icons.folder));
      expect(icon.color, Colors.blue);
      expect(icon.size, 48);
    });

    testWidgets('expand mode centers the fallback icon', (tester) async {
      await tester.pumpWidget(wrap(SizedBox(
        width: 200,
        height: 200,
        child: CoverArt(sampleTrack(), size: 384, expand: true, resolverForTest: resolver),
      )));

      expect(find.byType(Center), findsWidgets);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });
  });

  group('with cover art', () {
    Track trackWithCover() => sampleTrack(coverArtId: 'cov-1');

    testWidgets('the URL and cache key are built from the same size — never out of step', (tester) async {
      await tester.pumpWidget(wrap(
        CoverArt(trackWithCover(), size: 48, resolverForTest: resolver),
      ));

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      // Default test devicePixelRatio is 1.0, so the requested pixel size is
      // 48 either way — what matters is that both come from one value.
      expect(image.imageUrl, resolver.buildCoverArtUrl('cov-1', size: 48));
      expect(image.cacheKey, 'cover_cov-1_48');
    });

    testWidgets('a fixed size sets the box width and height to match', (tester) async {
      await tester.pumpWidget(wrap(
        CoverArt(trackWithCover(), size: 48, resolverForTest: resolver),
      ));

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.width, 48);
      expect(image.height, 48);
    });

    testWidgets('expand: true leaves width and height unset to fill its parent', (tester) async {
      await tester.pumpWidget(wrap(
        CoverArt(trackWithCover(), size: 384, expand: true, resolverForTest: resolver),
      ));

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.width, isNull);
      expect(image.height, isNull);
    });

    testWidgets('showPlaceholder: false (track tiles) leaves the placeholder unset', (tester) async {
      await tester.pumpWidget(wrap(CoverArt(
        trackWithCover(),
        size: 48,
        showPlaceholder: false,
        resolverForTest: resolver,
      )));

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.placeholder, isNull);
      expect(image.errorWidget, isNotNull); // the error fallback still shows
    });

    testWidgets('showPlaceholder: true (default, folder tiles) sets a placeholder', (tester) async {
      await tester.pumpWidget(wrap(
        CoverArt(trackWithCover(), size: 48, resolverForTest: resolver),
      ));

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.placeholder, isNotNull);
    });

    testWidgets('is clipped to radius by default, not clipped when radius: 0', (tester) async {
      await tester.pumpWidget(wrap(
        CoverArt(trackWithCover(), size: 48, resolverForTest: resolver),
      ));
      expect(find.byType(ClipRRect), findsOneWidget);

      await tester.pumpWidget(wrap(
        CoverArt(trackWithCover(), size: 384, radius: 0, resolverForTest: resolver),
      ));
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, BorderRadius.zero);
    });
  });
}
