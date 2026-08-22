import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anywhere_music_player/screens/home_screen.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import '../support/fake_path_provider.dart';
import '../support/fake_scanner.dart';
import '../support/fake_auth.dart';
import '../support/pump_helpers.dart';

Widget _wrap({
  required AuthService auth,
  required LibraryScanner scanner,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<AudioPlayerService>.value(value: AudioPlayerService()),
      ChangeNotifierProvider<LibraryScanner>.value(value: scanner),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('home_screen_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    SharedPreferences.setMockInitialValues({});

    // On a Windows test host, AudioPlayerService.stop() (called from
    // HomeScreen's logout flow) calls window_manager.setTitle() for real —
    // there's no plugin implementation under flutter test, so stub the channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (call) async => null);
  });

  tearDown(() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  testWidgets('greets the logged-in user and lists folders once the scan completes', (tester) async {
    final auth = await loggedInAuthService(username: 'alice');
    // A second top-level folder so "Anime" isn't the sole one — otherwise
    // it's the auto-flattened root and getTopLevelFolders() surfaces its
    // children instead (see LibraryScanner.isFlattenedRoot).
    final scanner = scannerWithSongs([
      nativeApiSong(id: '1', path: 'Anime/Naruto/song.mp3'),
      nativeApiSong(id: '2', path: 'Rock/song.mp3'),
    ]);

    await pumpAndWaitForAsyncWork(tester, _wrap(auth: auth, scanner: scanner), () => scanner.isScanning);
    await tester.pumpAndSettle();

    expect(find.text('Welcome, alice'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget); // top-level folder
    expect(find.textContaining('tracks'), findsWidgets); // "N tracks" header
  });

  testWidgets('shows a fatal error with a retry button when the scan fails', (tester) async {
    final auth = await loggedInAuthService();
    final scanner = LibraryScanner(failingSubsonicApiService());

    await pumpAndWaitForAsyncWork(tester, _wrap(auth: auth, scanner: scanner), () => scanner.isScanning);
    await tester.pumpAndSettle();

    // SubsonicApiException.toString() returns just its message (no "Exception: "
    // prefix — see SubsonicApiException).
    expect(find.text('Failed to scan library: Native API login failed: HTTP 500'),
        findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
  });

  testWidgets('searching debounces, then shows results or "No results found"', (tester) async {
    final auth = await loggedInAuthService();
    final scanner = scannerWithSongs([
      nativeApiSong(id: '1', path: 'Anime/Naruto/song.mp3'),
    ]);

    await pumpAndWaitForAsyncWork(tester, _wrap(auth: auth, scanner: scanner), () => scanner.isScanning);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'nothing matches this');
    await tester.pump(const Duration(milliseconds: 350)); // past the 300ms debounce
    await tester.pumpAndSettle();

    // The fake auth-service api echoes {"status":"ok"} with no searchResult3,
    // so search3() returns no songs and no library-tree folders match either.
    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('logout stops playback, clears the library, and logs out', (tester) async {
    final auth = await loggedInAuthService();
    final scanner = scannerWithSongs([nativeApiSong(id: '1', path: 'Anime/song.mp3')]);

    await pumpAndWaitForAsyncWork(tester, _wrap(auth: auth, scanner: scanner), () => scanner.isScanning);
    await tester.pumpAndSettle();
    expect(scanner.allTracks, isNotEmpty);

    // _handleLogout does real file I/O (LibraryCache.clear()) — same
    // zone-binding issue as scan()'s compute() call, so the tap that starts
    // it needs to happen inside runAsync too. See pumpAndWaitForAsyncWork.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Logout'));
      while (auth.isAuthenticated) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(auth.isAuthenticated, isFalse);
    expect(scanner.allTracks, isEmpty);
  });
}

/// A [SubsonicApiService] whose every request fails — for testing the fatal
/// scan-error path without a real server.
SubsonicApiService failingSubsonicApiService() => SubsonicApiService(
  serverUrl: 'https://navidrome.example.com',
  username: 'alice',
  password: 'secret',
  httpClient: MockClient((request) async => http.Response('Server Error', 500)),
);
