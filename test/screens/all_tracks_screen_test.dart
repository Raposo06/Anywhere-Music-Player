import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:anywhere_music_player/screens/all_tracks_screen.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import '../support/fake_path_provider.dart';
import '../support/fake_scanner.dart';
import '../support/fixtures.dart';
import '../support/pump_helpers.dart';

Widget _wrap({required LibraryScanner scanner, AudioPlayerService? player}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AudioPlayerService>.value(
        value: player ?? AudioPlayerService(),
      ),
      ChangeNotifierProvider<LibraryScanner>.value(value: scanner),
      // TrackTile carries a favourite heart, which reads this. A
      // logged-out service is the right stub: isStarred is false for
      // everything and toggle is a no-op.
      ChangeNotifierProvider<FavouritesService>(
        create: (_) => FavouritesService(null),
      ),
      // No cover art on any fixture in this file, so an unauthenticated
      // (apiService == null) AuthService resolves the same as a real one.
      ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
    ],
    child: const MaterialApp(home: AllTracksScreen()),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('all_tracks_screen_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
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

  testWidgets('lists all tracks alphabetically once the scanner has data', (
    tester,
  ) async {
    final scanner = scannerWithSongs([
      nativeApiSong(id: '1', path: 'Zebra Song.mp3'),
      nativeApiSong(id: '2', path: 'Apple Song.mp3'),
    ]);
    await tester.runAsync(() => scanner.scan());

    await tester.pumpWidget(_wrap(scanner: scanner));
    await settle(tester);

    expect(find.text('2 tracks'), findsOneWidget);
    final appleCenter = tester.getCenter(find.text('Apple Song'));
    final zebraCenter = tester.getCenter(find.text('Zebra Song'));
    expect(appleCenter.dy, lessThan(zebraCenter.dy)); // alphabetical
  });

  testWidgets('shows an empty state when the library has no tracks', (
    tester,
  ) async {
    final scanner = scannerWithSongs([]);
    await tester.runAsync(() => scanner.scan());

    await tester.pumpWidget(_wrap(scanner: scanner));
    await settle(tester);

    expect(find.text('No tracks found'), findsOneWidget);
  });

  testWidgets('searching filters the list by title, case-insensitively', (
    tester,
  ) async {
    final scanner = scannerWithSongs([
      nativeApiSong(id: '1', path: 'Naruto Opening.mp3'),
      nativeApiSong(id: '2', path: 'Bleach Opening.mp3'),
    ]);
    await tester.runAsync(() => scanner.scan());

    await tester.pumpWidget(_wrap(scanner: scanner));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'naruto');
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);

    expect(find.text('Naruto Opening'), findsOneWidget);
    expect(find.text('Bleach Opening'), findsNothing);
    expect(find.text('Results (1 tracks)'), findsOneWidget);
  });

  testWidgets(
    'swiping a track away adds it to the queue instead of restarting playback',
    (tester) async {
      final scanner = scannerWithSongs([
        nativeApiSong(id: '1', path: 'Some Song.mp3'),
      ]);
      await tester.runAsync(() => scanner.scan());
      // A track must already be playing, or addToQueue() would fall through to
      // playTrack() — which needs a live platform audio backend this test
      // doesn't have. See AudioPlayerService.addToQueue.
      final player = AudioPlayerService()
        ..seedForTest(
          currentTrack: sampleTrack(id: '0', title: 'Already Playing'),
        );

      await tester.pumpWidget(_wrap(scanner: scanner, player: player));
      await settle(tester);

      await tester.drag(find.text('Some Song'), const Offset(500, 0));
      await settle(tester);

      expect(player.queue.map((t) => t.title), ['Some Song']);
      expect(find.text('Added to queue: Some Song'), findsOneWidget);
    },
  );
}
