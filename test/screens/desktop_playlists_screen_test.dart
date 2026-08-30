import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anywhere_music_player/screens/desktop/desktop_playlists_screen.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/playlists_service.dart';
import '../support/fake_auth.dart';
import '../support/fake_just_audio.dart';
import '../support/fake_playlists.dart';
import '../support/fake_resolver.dart';

// Covers the desktop playlists screens — the counterpart to
// playlists_screen_test.dart, which does the same for the phone. The two
// layouts share PlaylistsService and diverge only in chrome, so this
// concentrates on what is actually different: the overflow menu (rename /
// delete) and the right-click removal path.
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
        '2': (name: 'Bob\'s mix', owner: 'bob', trackIds: ['c']),
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

  /// Several short pumps — pumpAndSettle would hang on a spinner's animation.
  Future<void> settle(WidgetTester tester, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    // These screens are laid out for a desktop window; the default 800x600
    // test surface overflows their header row. setSurfaceSize rather than
    // view.physicalSize — the latter needs resetting while the tree is still
    // mounted, which trips a framework assertion at teardown.
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaylistsService>.value(value: playlists),
          ChangeNotifierProvider<AudioPlayerService>.value(value: player),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          // DesktopTrackRow carries a favourite heart, which reads this.
          ChangeNotifierProvider<FavouritesService>(
            create: (_) => FavouritesService(null),
          ),
          // The playlists list pins an "All Tracks" row whose subtitle is the
          // library's track count.
          ChangeNotifierProvider<LibraryScanner>(
            create: (_) => LibraryScanner(null),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: home)),
      ),
    );
    await settle(tester);
  }

  group('the list', () {
    testWidgets('shows each playlist with its summary', (tester) async {
      await pump(tester, const DesktopPlaylistsScreen());

      expect(find.text('Roadtrip'), findsOneWidget);
      expect(find.text('2 tracks · 2 min'), findsOneWidget);
      expect(find.text('2 playlists'), findsOneWidget);
    });

    testWidgets('only playlists the user owns get an overflow menu', (
      tester,
    ) async {
      await pump(tester, const DesktopPlaylistsScreen());

      expect(find.textContaining('read-only'), findsOneWidget);
      // One menu button — Roadtrip's, not Bob's.
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });

    testWidgets('renaming it through the overflow menu sticks', (tester) async {
      await pump(tester, const DesktopPlaylistsScreen());

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Long drive');
      await tester.tap(find.text('Rename'));
      await settle(tester, frames: 8);

      expect(server.playlists['1']!.name, 'Long drive');
      expect(find.text('Long drive'), findsOneWidget);
    });

    testWidgets('deleting through the overflow menu asks first', (
      tester,
    ) async {
      await pump(tester, const DesktopPlaylistsScreen());

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Roadtrip"?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester, frames: 8);

      expect(server.playlists.keys, ['2']);
    });

    testWidgets('pins All Tracks above the user\'s own playlists', (
      tester,
    ) async {
      await pump(tester, const DesktopPlaylistsScreen());

      expect(find.text('All Tracks'), findsOneWidget);
      // A library view has nothing to rename or delete, so it gets no
      // overflow menu — only Roadtrip (owned) does.
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });

    testWidgets('All Tracks is still there when there are no playlists', (
      tester,
    ) async {
      server.playlists.clear();
      await pump(tester, const DesktopPlaylistsScreen());

      expect(find.text('All Tracks'), findsOneWidget);
      expect(find.text('No playlists yet'), findsOneWidget);
    });

    testWidgets('with none, it says so', (tester) async {
      server.playlists.clear();
      await pump(tester, const DesktopPlaylistsScreen());

      expect(find.text('No playlists yet'), findsOneWidget);
    });
  });

  group('one playlist', () {
    testWidgets('lists its tracks in order', (tester) async {
      await pump(tester, const DesktopPlaylistScreen(playlistId: '1'));

      expect(find.text('Song a'), findsOneWidget);
      expect(find.text('Song b'), findsOneWidget);
    });

    testWidgets('an empty one says so rather than looking stuck', (
      tester,
    ) async {
      server.playlists['1'] = (name: 'Roadtrip', owner: 'alice', trackIds: []);
      await pump(tester, const DesktopPlaylistScreen(playlistId: '1'));

      expect(find.text('This playlist is empty.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('right-click offers removal, and removing works', (
      tester,
    ) async {
      await pump(tester, const DesktopPlaylistScreen(playlistId: '1'));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Song a')),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Remove from playlist'), findsOneWidget);
      await tester.tap(find.text('Remove from playlist'));
      await settle(tester, frames: 8);

      expect(server.playlists['1']!.trackIds, ['b']);
      expect(find.text('Song a'), findsNothing);
    });

    testWidgets('a playlist owned by someone else offers no removal', (
      tester,
    ) async {
      await pump(tester, const DesktopPlaylistScreen(playlistId: '2'));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Song c')),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // Queue and add-to-playlist are still offered; removal is not.
      expect(find.text('Add to queue'), findsOneWidget);
      expect(find.text('Remove from playlist'), findsNothing);
    });
  });
}
