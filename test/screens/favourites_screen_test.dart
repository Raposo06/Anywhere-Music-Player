import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:anywhere_music_player/screens/favourites_screen.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import '../support/fake_just_audio.dart';
import '../support/fake_resolver.dart';

// Covers the phone Favourites screen: its empty, error and populated states,
// and that tapping a row starts playback from the favourites list rather than
// from whatever was playing before.
//
// The desktop counterpart (DesktopFavouritesScreen) shares FavouritesService
// with this and differs only in chrome — see docs/decisions.md.

http.Response _ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
);

http.Response _failed(String message) => http.Response(
  jsonEncode({
    'subsonic-response': {
      'status': 'failed',
      'error': {'code': 70, 'message': message},
    },
  }),
  200,
);

Map<String, dynamic> _song(String id, String title) => {
  'id': id,
  'title': title,
  'path': '$title.mp3',
  'duration': 180,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Without a fake platform, AudioPlayerService's stream open never resolves
  // and its 12s retry timeout is left pending, which fails the test — see
  // _setSourceWithRetry. Same harness the playback tests use.
  const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  late AudioPlayerService player;

  setUp(() {
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    player = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, (call) async => null);
  });

  tearDown(() {
    player.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, null);
  });

  FavouritesService buildService(http.Response Function() respond) {
    return FavouritesService(
      SubsonicApiService(
        serverUrl: 'https://navidrome.example.com',
        username: 'a',
        password: 'p',
        httpClient: MockClient((_) async => respond()),
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    FavouritesService favourites,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerService>.value(value: player),
          ChangeNotifierProvider<FavouritesService>.value(value: favourites),
          // No cover art on these fixtures, so an unauthenticated AuthService
          // resolves the same as a real one — same shortcut the other screen
          // tests take.
          ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ],
        child: const MaterialApp(home: FavouritesScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('with no favourites, invites the user to add one', (
    tester,
  ) async {
    final favourites = buildService(() => _ok({'starred2': {}}));
    await favourites.load();

    await pumpScreen(tester, favourites);

    expect(find.text('No favourites yet'), findsOneWidget);
    expect(
      find.text('Tap the heart on any track to keep it here.'),
      findsOneWidget,
    );
    // Nothing to play, so the header actions stay out of the way.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.shuffle), findsNothing);
  });

  testWidgets('lists starred tracks in the order the server gave them', (
    tester,
  ) async {
    final favourites = buildService(
      () => _ok({
        'starred2': {
          'song': [_song('1', 'Newest'), _song('2', 'Older')],
        },
      }),
    );
    await favourites.load();

    await pumpScreen(tester, favourites);

    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Older'), findsOneWidget);
    // With tracks present, play-all and shuffle appear.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.shuffle), findsOneWidget);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    final favourites = buildService(() => _failed('server said no'));
    await favourites.load();

    await pumpScreen(tester, favourites);

    expect(find.textContaining('Could not load favourites'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping a track plays it from the favourites list', (
    tester,
  ) async {
    final favourites = buildService(
      () => _ok({
        'starred2': {
          'song': [_song('1', 'First'), _song('2', 'Second')],
        },
      }),
    );
    await favourites.load();
    await pumpScreen(tester, favourites);

    // The tap runs inside runAsync deliberately. It is what first creates the
    // AudioPlayer, and just_audio's position stream (which the scrobble
    // watcher subscribes to) starts a periodic timer in whichever zone that
    // happens in — created in the fake-async zone it would still be pending
    // when the test ends, which testWidgets fails on. It also lets the
    // platform futures for the stream open actually complete.
    await tester.runAsync(() async {
      await tester.tap(find.text('Second'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(player.currentTrack?.id, '2');
    // The whole favourites list becomes the playlist, so playback continues
    // through it rather than stopping after one track.
    expect(player.playlist.map((t) => t.id), ['1', '2']);

    // Disposed here, in the fake-async zone, then pumped: just_audio's
    // position stream (which the scrobble watcher subscribes to) holds a
    // periodic timer registered in that zone, and testWidgets fails a test
    // that ends with one pending. Cancelling it from runAsync's real zone
    // does not clear it — the pump is what flushes the cancellation.
    player.dispose();
  });
}
