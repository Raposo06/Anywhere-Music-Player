import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:anywhere_music_player/screens/folder_detail_screen.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import '../support/fake_path_provider.dart';
import '../support/fake_scanner.dart';
import '../support/fixtures.dart';
import '../support/pump_helpers.dart';

Widget _wrap({
  required LibraryScanner scanner,
  required String folderId,
  required String folderName,
  AudioPlayerService? player,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AudioPlayerService>.value(value: player ?? AudioPlayerService()),
      ChangeNotifierProvider<LibraryScanner>.value(value: scanner),
    ],
    child: MaterialApp(
      home: FolderDetailScreen(folderId: folderId, folderName: folderName),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('folder_detail_screen_test_');
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

  testWidgets('lists subfolders and tracks at the given path', (tester) async {
    final scanner = scannerWithSongs([
      nativeApiSong(id: '1', path: 'Anime/Naruto/song.mp3'),
      nativeApiSong(id: '2', path: 'Anime/loose.mp3'),
    ]);
    await tester.runAsync(() => scanner.scan());

    await tester.pumpWidget(_wrap(scanner: scanner, folderId: 'Anime', folderName: 'Anime'));
    await settle(tester);

    expect(find.text('Naruto'), findsOneWidget); // subfolder
    expect(find.text('loose'), findsOneWidget); // direct track
    expect(find.text('1 track(s)'), findsOneWidget); // recursive total
  });

  testWidgets('shows "No content found" for a path with nothing in it', (tester) async {
    final scanner = scannerWithSongs([nativeApiSong(id: '1', path: 'Anime/song.mp3')]);
    await tester.runAsync(() => scanner.scan());

    await tester.pumpWidget(_wrap(scanner: scanner, folderId: 'Nonexistent', folderName: 'Nonexistent'));
    await settle(tester);

    expect(find.text('No content found'), findsOneWidget);
  });

  testWidgets('shows a breadcrumb (Home + parent) for a nested folder', (tester) async {
    // A second, unrelated top-level folder so "Anime" isn't the sole
    // top-level entry — otherwise it's the auto-flattened root and the
    // breadcrumb deliberately omits it (see LibraryScanner.isFlattenedRoot).
    final scanner = scannerWithSongs([
      nativeApiSong(id: '1', path: 'Anime/Naruto/song.mp3'),
      nativeApiSong(id: '2', path: 'Rock/song.mp3'),
    ]);
    await tester.runAsync(() => scanner.scan());

    await tester.pumpWidget(_wrap(scanner: scanner, folderId: 'Anime/Naruto', folderName: 'Naruto'));
    await settle(tester);

    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget); // clickable parent crumb
  });

  testWidgets('search filters tracks within the folder', (tester) async {
    final scanner = scannerWithSongs([
      nativeApiSong(id: '1', path: 'Anime/Naruto Opening.mp3'),
      nativeApiSong(id: '2', path: 'Anime/Bleach Opening.mp3'),
    ]);
    await tester.runAsync(() => scanner.scan());

    await tester.pumpWidget(_wrap(scanner: scanner, folderId: 'Anime', folderName: 'Anime'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'naruto');
    await tester.pump();

    expect(find.text('Naruto Opening'), findsOneWidget);
    expect(find.text('Bleach Opening'), findsNothing);
  });

  testWidgets('search with no matches shows the empty-search message', (tester) async {
    final scanner = scannerWithSongs([nativeApiSong(id: '1', path: 'Anime/Naruto Opening.mp3')]);
    await tester.runAsync(() => scanner.scan());

    await tester.pumpWidget(_wrap(scanner: scanner, folderId: 'Anime', folderName: 'Anime'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pump();

    expect(find.text('No tracks match your search'), findsOneWidget);
  });

  testWidgets('swiping a track away adds it to the queue', (tester) async {
    final scanner = scannerWithSongs([nativeApiSong(id: '1', path: 'Anime/Some Song.mp3')]);
    await tester.runAsync(() => scanner.scan());
    final player = AudioPlayerService()..seedForTest(currentTrack: sampleTrack(id: '0', title: 'Already Playing'));

    await tester.pumpWidget(_wrap(scanner: scanner, folderId: 'Anime', folderName: 'Anime', player: player));
    await settle(tester);

    await tester.drag(find.text('Some Song'), const Offset(500, 0));
    await settle(tester);

    expect(player.queue.map((t) => t.title), ['Some Song']);
  });
}
