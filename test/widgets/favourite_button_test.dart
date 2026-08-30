import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import 'package:anywhere_music_player/theme/app_colors.dart';
import 'package:anywhere_music_player/widgets/desktop/favourite_button.dart';
import '../support/fixtures.dart';

// Covers the heart itself: that it reflects starred state, toggles on tap, and
// obeys the show/hide rule rows depend on — hidden until hovered when
// unstarred, always visible once starred.

http.Response _ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
);

void main() {
  /// A service whose requests all succeed, recording the endpoints hit.
  ({FavouritesService favourites, List<String> endpoints}) build({
    List<Map<String, dynamic>> starred = const [],
  }) {
    final endpoints = <String>[];
    final client = MockClient((request) async {
      final endpoint = request.url.path.split('/').last;
      endpoints.add(endpoint);
      if (endpoint == 'getStarred2') {
        return _ok({
          'starred2': {'song': starred},
        });
      }
      return _ok({});
    });
    return (
      favourites: FavouritesService(
        SubsonicApiService(
          serverUrl: 'https://navidrome.example.com',
          username: 'a',
          password: 'p',
          httpClient: client,
        ),
      ),
      endpoints: endpoints,
    );
  }

  Future<void> pumpButton(
    WidgetTester tester,
    FavouritesService favourites, {
    bool visible = true,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FavouritesService>.value(
        value: favourites,
        child: MaterialApp(
          home: Scaffold(
            body: FavouriteButton(
              track: sampleTrack(id: '1'),
              visible: visible,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Icon icon(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon).first);

  /// The tint lives on the IconButton — the Icon inherits it through
  /// IconTheme and carries no colour of its own.
  Color? tint(WidgetTester tester) =>
      tester.widget<IconButton>(find.byType(IconButton)).color;

  double opacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('shows an outline heart when the track is not starred', (
    tester,
  ) async {
    final (:favourites, endpoints: _) = build();
    await pumpButton(tester, favourites);

    expect(icon(tester).icon, Icons.favorite_border);
    expect(tint(tester), AppColors.faint);
  });

  testWidgets('shows a filled accent heart when starred', (tester) async {
    final (:favourites, endpoints: _) = build(
      starred: [
        {'id': '1', 'title': 'Starred', 'path': 'Starred.mp3'},
      ],
    );
    await favourites.load();
    await pumpButton(tester, favourites);

    expect(icon(tester).icon, Icons.favorite);
    expect(tint(tester), AppColors.accent);
  });

  testWidgets('tapping stars the track', (tester) async {
    final (:favourites, :endpoints) = build();
    await pumpButton(tester, favourites);

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    // Optimistic: filled before the request is even answered.
    expect(icon(tester).icon, Icons.favorite);
    await tester.pumpAndSettle();
    expect(endpoints, ['star']);
  });

  testWidgets('tapping again unstars it', (tester) async {
    final (:favourites, :endpoints) = build(
      starred: [
        {'id': '1', 'title': 'Starred', 'path': 'Starred.mp3'},
      ],
    );
    await favourites.load();
    await pumpButton(tester, favourites);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(icon(tester).icon, Icons.favorite_border);
    expect(endpoints, ['getStarred2', 'unstar']);
  });

  group('visibility', () {
    testWidgets('an unstarred heart is hidden when not visible', (
      tester,
    ) async {
      final (:favourites, endpoints: _) = build();
      await pumpButton(tester, favourites, visible: false);

      expect(opacity(tester), 0);
      // Still laid out, so the row doesn't reflow when the pointer arrives.
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('a hidden heart cannot be tapped', (tester) async {
      final (:favourites, :endpoints) = build();
      await pumpButton(tester, favourites, visible: false);

      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(endpoints, isEmpty);
      expect(favourites.isStarred('1'), isFalse);
    });

    testWidgets('a starred heart shows even when not visible', (tester) async {
      // Starred is state, not an affordance — it must not depend on hover.
      final (:favourites, endpoints: _) = build(
        starred: [
          {'id': '1', 'title': 'Starred', 'path': 'Starred.mp3'},
        ],
      );
      await favourites.load();
      await pumpButton(tester, favourites, visible: false);

      expect(opacity(tester), 1);
      expect(icon(tester).icon, Icons.favorite);
    });
  });
}
