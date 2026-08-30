import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anywhere_music_player/screens/desktop/desktop_playlists_screen.dart';
import 'package:anywhere_music_player/screens/desktop/desktop_shell.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/playlists_service.dart';
import '../support/fake_auth.dart';
import '../support/fake_just_audio.dart';
import '../support/fake_playlists.dart';
import '../support/fake_resolver.dart';

// Covers the window chrome's back chevron, which lives in the shell rather
// than on the individual screens — see the "Alt + ← and Escape go back on
// desktop" entry in docs/decisions.md, which added the keyboard shortcut but
// left the chrome with no visible click target for the same action.
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
  Future<void> settle(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaylistsService>.value(value: playlists),
          ChangeNotifierProvider<AudioPlayerService>.value(value: player),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<FavouritesService>(
            create: (_) => FavouritesService(null),
          ),
          ChangeNotifierProvider<LibraryScanner>(
            create: (_) => LibraryScanner(null),
          ),
        ],
        child: const MaterialApp(home: DesktopShell()),
      ),
    );
    await settle(tester);
  }

  testWidgets('sitting at a destination root shows no back chevron', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byTooltip('Back (Esc)'), findsNothing);
  });

  testWidgets('opening a playlist shows the chevron, and it goes back', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Playlists'));
    await settle(tester);
    expect(find.byTooltip('Back (Esc)'), findsNothing);

    await tester.tap(find.text('Roadtrip'));
    await settle(tester);

    expect(find.byType(DesktopPlaylistScreen), findsOneWidget);
    expect(find.byTooltip('Back (Esc)'), findsOneWidget);
    // The title bar's context line follows the drill-down, same as it does
    // for a folder.
    expect(find.textContaining('Roadtrip'), findsWidgets);

    await tester.tap(find.byTooltip('Back (Esc)'));
    // Unlike the other assertions here, this pop is a real MaterialPageRoute
    // transition (~300ms), not a dialog — the default settle() isn't long
    // enough to let DesktopPlaylistScreen actually leave the tree.
    await settle(tester, frames: 16);

    expect(find.byType(DesktopPlaylistScreen), findsNothing);
    expect(find.byTooltip('Back (Esc)'), findsNothing);
  });

  testWidgets('switching to Favourites never shows a chevron', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Favourites'));
    await settle(tester);

    // Favourites is flat — there is nothing under it to go back through.
    expect(find.byTooltip('Back (Esc)'), findsNothing);
  });
}
