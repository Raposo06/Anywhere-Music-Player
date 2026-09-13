import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anywhere_music_player/screens/desktop/desktop_player_screen.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/widgets/desktop/desktop_mini_player.dart';
import '../support/fake_auth.dart';
import '../support/fake_resolver.dart';
import '../support/fixtures.dart';

// Covers the transport buttons on Now Playing and the mini player: whether
// Next and Previous are live is the service's answer (canGoNext /
// canGoPrevious), and both transports must give the same one. Until
// 2026-09-13 Now Playing derived it from playlist.length and disabled Next
// with one track playing and another queued, while the mini player never
// disabled either — see docs/decisions.md.
//
// Playback state is seeded, never loaded: seedForTest doesn't touch the
// native player, so nothing here leaves a load timeout or position poll
// pending past the end of the test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AudioPlayerService player;
  late AuthService auth;

  setUp(() async {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
    SharedPreferences.setMockInitialValues({});
    auth = await loggedInAuthService();
    player = AudioPlayerService(resolver: const FakeStreamUrlResolver());
  });

  tearDown(() => player.dispose());

  Future<void> settle(WidgetTester tester, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerService>.value(value: player),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<FavouritesService>(
            create: (_) => FavouritesService(null),
          ),
          ChangeNotifierProvider<LibraryScanner>(
            create: (_) => LibraryScanner(null),
          ),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  bool isLive(WidgetTester tester, String tooltip) {
    final button = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          )
          .first,
    );
    return button.onPressed != null;
  }

  final one = sampleTrack(id: 'a', title: 'Only');
  final queued = sampleTrack(id: 'q', title: 'Queued');

  group('Now Playing', () {
    testWidgets('one track, repeat off: Next and Previous are both off', (
      tester,
    ) async {
      player.seedForTest(
        playlist: [one],
        currentIndex: 0,
        currentTrack: one,
        repeatMode: RepeatMode.off,
      );
      await pump(tester, const DesktopPlayerScreen());

      expect(isLive(tester, 'Next (Ctrl+→)'), isFalse);
      expect(isLive(tester, 'Previous (Ctrl+←)'), isFalse);
    });

    testWidgets('queueing a track makes Next live — the regression', (
      tester,
    ) async {
      player.seedForTest(
        playlist: [one],
        currentIndex: 0,
        currentTrack: one,
        queue: [queued],
        repeatMode: RepeatMode.off,
      );
      await pump(tester, const DesktopPlayerScreen());

      expect(isLive(tester, 'Next (Ctrl+→)'), isTrue);
      expect(isLive(tester, 'Previous (Ctrl+←)'), isFalse);
    });

    testWidgets('the buttons follow the service as it changes', (tester) async {
      player.seedForTest(
        playlist: [one],
        currentIndex: 0,
        currentTrack: one,
        repeatMode: RepeatMode.off,
      );
      await pump(tester, const DesktopPlayerScreen());
      expect(isLive(tester, 'Next (Ctrl+→)'), isFalse);

      player.toggleRepeatMode(); // off → all: Next now replays the track
      await settle(tester);

      expect(isLive(tester, 'Next (Ctrl+→)'), isTrue);
    });
  });

  group('mini player', () {
    testWidgets('gives the same answer as Now Playing', (tester) async {
      player.seedForTest(
        playlist: [one],
        currentIndex: 0,
        currentTrack: one,
        queue: [queued],
        repeatMode: RepeatMode.off,
      );
      await pump(
        tester,
        Scaffold(body: DesktopMiniPlayer(onOpenPlayer: () {})),
      );

      expect(isLive(tester, 'Next (Ctrl+→)'), isTrue);
      expect(isLive(tester, 'Previous (Ctrl+←)'), isFalse);
    });
  });
}
