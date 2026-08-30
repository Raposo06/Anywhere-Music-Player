import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import 'package:anywhere_music_player/widgets/desktop/desktop_track_row.dart';
import '../support/fake_resolver.dart';
import '../support/fixtures.dart';

// Covers DesktopTrackRow rendering with its favourite heart — in particular
// the HoverRow `builder` path the heart needs, which nothing else exercises:
// passing neither child nor builder trips an assert only at runtime.
void main() {
  late AudioPlayerService player;

  setUp(() {
    player = AudioPlayerService(resolver: const FakeStreamUrlResolver());
  });

  tearDown(() => player.dispose());

  FavouritesService buildFavourites({
    List<Map<String, dynamic>> starred = const [],
  }) {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'subsonic-response': {
            'status': 'ok',
            'starred2': {'song': starred},
          },
        }),
        200,
      );
    });
    return FavouritesService(
      SubsonicApiService(
        serverUrl: 'https://navidrome.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      ),
    );
  }

  Future<void> pumpRow(
    WidgetTester tester,
    FavouritesService favourites,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerService>.value(value: player),
          ChangeNotifierProvider<FavouritesService>.value(value: favourites),
          // CoverArt resolves through AuthService. The fixture has no cover
          // art, so an unauthenticated one resolves the same as a real one —
          // same shortcut track_tile_test.dart takes.
          ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DesktopTrackRow(
              track: sampleTrack(id: '1', title: 'A Song'),
              number: 1,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the track with a heart', (tester) async {
    await pumpRow(tester, buildFavourites());

    expect(find.text('A Song'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('the heart is hidden until the row is hovered', (tester) async {
    await pumpRow(tester, buildFavourites());

    final opacity = tester
        .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .opacity;
    expect(opacity, 0, reason: 'not hovered, and not a favourite');
  });

  testWidgets('a starred track shows a filled heart without hovering', (
    tester,
  ) async {
    final favourites = buildFavourites(
      starred: [
        {'id': '1', 'title': 'A Song', 'path': 'A Song.mp3'},
      ],
    );
    await favourites.load();

    await pumpRow(tester, favourites);

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
  });
}
