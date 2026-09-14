import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/screens/desktop/desktop_library_screen.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/screens/desktop/shell_navigation.dart';
import '../support/fake_auth.dart';
import '../support/fake_navigation.dart';
import '../support/fake_scanner.dart';

/// Records what the screen asks to play instead of loading it. A real load
/// leaves just_audio's position poll and load timeout pending past the end
/// of a widget test; what this screen is responsible for is the *list* it
/// hands over, which is all this keeps.
class _RecordingPlayer extends AudioPlayerService {
  List<Track>? played;
  List<Track>? shuffled;

  @override
  Future<void> play(List<Track> tracks, {int from = 0}) async {
    played = tracks;
  }

  @override
  Future<void> playShuffled(List<Track> tracks) async {
    shuffled = tracks;
  }
}

// Covers the Library header's whole-library verbs. "All Tracks" used to be a
// server-side playlist; Gonic cannot serve one this size (docs/decisions.md,
// 2026-09-13), so playing or shuffling everything is done from the scanner.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPlayer player;
  late AuthService auth;
  late RecordingShellNavigation navigation;

  // What the fake server browses to; the scanner walks it for real.
  final library = [
    browseSong(id: '1', path: 'Rock/One.mp3'),
    browseSong(id: '2', path: 'Rock/Two.mp3'),
    browseSong(id: '3', path: 'Soul/Three.mp3'),
  ];

  setUp(() async {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
    SharedPreferences.setMockInitialValues({});
    auth = await loggedInAuthService();
    player = _RecordingPlayer();
    navigation = RecordingShellNavigation();
  });

  tearDown(() => player.dispose());

  Future<void> settle(WidgetTester tester, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> songs,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final scanner = scannerWithSongs(songs);
    await tester.runAsync(scanner.scan);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ShellNavigation>.value(value: navigation),
          ChangeNotifierProvider<LibraryScanner>.value(value: scanner),
          ChangeNotifierProvider<AudioPlayerService>.value(value: player),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<FavouritesService>(
            create: (_) => FavouritesService(null),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: DesktopLibraryScreen())),
      ),
    );
    await settle(tester);
  }

  testWidgets('Play All plays the whole library in order', (tester) async {
    await pump(tester, library);

    await tester.tap(find.text('Play All'));
    await settle(tester);

    expect(player.played?.map((t) => t.id), ['1', '2', '3']);
    expect(player.shuffled, isNull);
    expect(navigation.nowPlayingOpened, 1);
  });

  testWidgets('Shuffle plays the whole library, shuffled', (tester) async {
    await pump(tester, library);

    await tester.tap(find.text('Shuffle'));
    await settle(tester);

    expect(player.shuffled?.map((t) => t.id), ['1', '2', '3']);
    expect(player.played, isNull);
    expect(navigation.nowPlayingOpened, 1);
  });

  testWidgets('both are disabled while the library is empty', (tester) async {
    await pump(tester, const []);

    expect(
      tester
          .widget<ElevatedButton>(
            find.ancestor(
              of: find.text('Play All'),
              matching: find.byType(ElevatedButton),
            ),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Shuffle'),
              matching: find.byType(OutlinedButton),
            ),
          )
          .enabled,
      isFalse,
    );
  });
}
