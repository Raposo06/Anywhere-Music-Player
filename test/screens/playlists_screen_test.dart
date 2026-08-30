import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anywhere_music_player/screens/playlists_screen.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/playlists_service.dart';
import '../support/fake_auth.dart';
import '../support/fake_just_audio.dart';
import '../support/fake_playlists.dart';
import '../support/fake_resolver.dart';

// Covers the phone playlists screens: the list (empty, populated, delete,
// ownership) and one playlist's detail (loading, empty, play, remove).
//
// Driven against FakePlaylistServer, which applies writes for real, so these
// assert on what the user ends up seeing rather than on requests sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  late FakePlaylistServer server;
  late PlaylistsService playlists;
  late AudioPlayerService player;
  late AuthService auth;

  setUp(() async {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
    SharedPreferences.setMockInitialValues({});
    auth = await loggedInAuthService();

    JustAudioPlatform.instance = FakeJustAudioPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, (call) async => null);

    server = FakePlaylistServer(
      playlists: {
        '1': (name: 'Roadtrip', owner: 'alice', trackIds: ['a', 'b']),
        '2': (name: 'Bob\'s mix', owner: 'bob', trackIds: []),
      },
    );
    playlists = server.service();
    player = AudioPlayerService(resolver: const FakeStreamUrlResolver());
  });

  tearDown(() {
    player.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, null);
  });

  /// Several short pumps. Used instead of pumpAndSettle, which would hang on
  /// a CircularProgressIndicator's endless animation.
  Future<void> settle(WidgetTester tester, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaylistsService>.value(value: playlists),
          ChangeNotifierProvider<AudioPlayerService>.value(value: player),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          // TrackTile carries a favourite heart, which reads this. Logged out
          // is the right stub — this file is about playlists, not stars.
          ChangeNotifierProvider<FavouritesService>(
            create: (_) => FavouritesService(null),
          ),
          // The playlists list pins an "All Tracks" row whose subtitle is the
          // library's track count.
          ChangeNotifierProvider<LibraryScanner>(
            create: (_) => LibraryScanner(null),
          ),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  group('the list', () {
    testWidgets('shows each playlist with its summary', (tester) async {
      await pump(tester, const PlaylistsScreen());

      expect(find.text('Roadtrip'), findsOneWidget);
      expect(find.text('2 tracks · 2 min'), findsOneWidget);
    });

    testWidgets('offers delete only on playlists the user owns', (
      tester,
    ) async {
      await pump(tester, const PlaylistsScreen());

      expect(find.textContaining('read-only'), findsOneWidget);
      // One delete button — for Roadtrip, not for Bob's.
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes it', (tester) async {
      await pump(tester, const PlaylistsScreen());

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(find.text('Delete "Roadtrip"?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);

      expect(server.playlists.keys, ['2']);
      expect(find.text('Roadtrip'), findsNothing);
    });

    testWidgets('cancelling the delete keeps it', (tester) async {
      await pump(tester, const PlaylistsScreen());

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);

      expect(server.playlists.containsKey('1'), isTrue);
      expect(find.text('Roadtrip'), findsOneWidget);
    });

    testWidgets('creating one opens it, rather than leaving you on the list', (
      tester,
    ) async {
      await pump(tester, const PlaylistsScreen());

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Fresh');
      await tester.tap(find.text('Create'));
      await settle(tester, frames: 8);

      // It exists on the server...
      expect(
        server.playlists.values.where((p) => p.name == 'Fresh'),
        hasLength(1),
      );
      // ...and we are now inside it, where the next step is adding songs.
      // A name alone would otherwise be a dead end.
      expect(find.text('This playlist is empty'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add songs'), findsOneWidget);
    });

    testWidgets('a smart playlist the user owns still gets no delete button', (
      tester,
    ) async {
      // All Tracks is a Navidrome smart playlist (.nsp): owned by the user,
      // but read-only. Ownership alone would wrongly offer delete — the
      // server's `readonly` flag is what stops it.
      server.playlists['3'] = (
        name: 'All Tracks',
        owner: 'alice',
        trackIds: ['a'],
      );
      server.readonlyIds.add('3');
      await pump(tester, const PlaylistsScreen());

      expect(find.text('All Tracks'), findsOneWidget);
      expect(find.textContaining('read-only'), findsWidgets);
      // Still only Roadtrip's — not All Tracks', despite alice owning both.
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('with none, it says so and invites creating one', (
      tester,
    ) async {
      server.playlists.clear();
      await pump(tester, const PlaylistsScreen());

      expect(find.text('No playlists yet'), findsOneWidget);
      // The subtitle is the "invites creating one" part — worth its own
      // assertion, since it was previously dropped without a test noticing.
      expect(
        find.text('Create one with +, or long-press a track to add it to one.'),
        findsOneWidget,
      );
    });
  });

  group('one playlist', () {
    testWidgets('lists its tracks in order', (tester) async {
      await pump(tester, const PlaylistScreen(playlistId: '1'));

      expect(find.text('Song a'), findsOneWidget);
      expect(find.text('Song b'), findsOneWidget);
    });

    testWidgets('an empty one says so rather than looking stuck', (
      tester,
    ) async {
      // The distinction that matters: not-fetched shows a spinner, genuinely
      // empty shows this.
      await pump(tester, const PlaylistScreen(playlistId: '2'));

      expect(find.text('This playlist is empty'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tapping a track plays from the playlist', (tester) async {
      await pump(tester, const PlaylistScreen(playlistId: '1'));

      // Inside runAsync so the AudioPlayer — and just_audio's periodic
      // position timer — are created in the real zone, not the fake-async one
      // where a pending timer would fail the test.
      await tester.runAsync(() async {
        await tester.tap(find.text('Song b'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(player.currentTrack?.id, 'b');
      expect(player.playlist.map((t) => t.id), ['a', 'b']);
    });

    testWidgets('long-press offers to remove, and removing works', (
      tester,
    ) async {
      await pump(tester, const PlaylistScreen(playlistId: '1'));

      await tester.longPress(find.text('Song a'));
      await settle(tester);
      expect(find.text('Remove from this playlist'), findsOneWidget);

      await tester.tap(find.text('Remove from this playlist'));
      await settle(tester, frames: 8);

      expect(server.playlists['1']!.trackIds, ['b']);
      expect(find.text('Song a'), findsNothing);
    });

    testWidgets('a playlist owned by someone else offers no removal', (
      tester,
    ) async {
      server.playlists['2'] = (
        name: 'Bob\'s mix',
        owner: 'bob',
        trackIds: ['c'],
      );
      await pump(tester, const PlaylistScreen(playlistId: '2'));

      await tester.longPress(find.text('Song c'));
      await settle(tester);

      // Straight to the picker — no remove option, because it isn't editable.
      expect(find.text('Remove from this playlist'), findsNothing);
    });
  });
}
