import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import '../support/fake_path_provider.dart';

Map<String, dynamic> _song({
  required String id,
  required String path,
  String? coverArtId,
}) => {
  'id': id,
  'path': path,
  'title': path.split('/').last,
  'coverArtId': coverArtId,
  'duration': 120,
  'size': 1000,
  'artist': 'Some Artist',
  'album': 'Some Album',
};

/// Mocks the native-API endpoints LibraryScanner.scan() drives:
/// POST /auth/login → {"token": ...}, then paginated GET /api/song.
/// A single page (< pageSize=500) ends the pagination loop.
http.Client _nativeApiClient(List<Map<String, dynamic>> songs) {
  return MockClient((request) async {
    if (request.method == 'POST' && request.url.path == '/auth/login') {
      return http.Response(jsonEncode({'token': 'fake-jwt'}), 200);
    }
    if (request.method == 'GET' && request.url.path == '/api/song') {
      final start = int.parse(request.url.queryParameters['_start']!);
      final page = songs.skip(start).take(500).toList();
      return http.Response(jsonEncode(page), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library_scanner_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    // scan() fires LibraryCache.save() without awaiting it (by design — see
    // library_cache.dart), so it can still be mid-write here. Retry the
    // cleanup instead of racing it.
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  SubsonicApiService apiWith(List<Map<String, dynamic>> songs) => SubsonicApiService(
    serverUrl: 'https://navidrome.example.com',
    username: 'alice',
    password: 'secret',
    httpClient: _nativeApiClient(songs),
  );

  group('with no api connection', () {
    test('hasApi is false and scan() sets a fatal error', () async {
      final scanner = LibraryScanner(null);

      await scanner.scan();

      expect(scanner.hasApi, isFalse);
      expect(scanner.error, isNotNull);
      expect(scanner.hasInitialData, isFalse);
    });
  });

  group('scan()', () {
    test('fetches songs and builds the virtual folder tree from their paths', () async {
      final scanner = LibraryScanner(apiWith([
        _song(id: '1', path: 'Anime/Naruto/01 - Opening.mp3'),
        _song(id: '2', path: 'Rock/Album/02 - Song.mp3'),
      ]));

      await scanner.scan();

      expect(scanner.hasInitialData, isTrue);
      expect(scanner.error, isNull);
      expect(scanner.allTracks, hasLength(2));

      final topLevel = scanner.getTopLevelFolders().map((f) => f.folderPath).toList();
      expect(topLevel, ['Anime', 'Rock']); // alphabetically sorted
    });

    test('populates folderName on scanned tracks (was left empty by the old inline parser)', () async {
      final scanner = LibraryScanner(apiWith([
        _song(id: '1', path: 'Anime/Naruto/01 - Opening.mp3'),
      ]));

      await scanner.scan();

      expect(scanner.allTracks.single.folderName, 'Naruto');
    });

    test('getFolderContents drills into a nested subfolder', () async {
      final scanner = LibraryScanner(apiWith([
        _song(id: '1', path: 'Anime/Naruto/01 - Opening.mp3'),
      ]));
      await scanner.scan();

      final animeContents = scanner.getFolderContents('Anime');
      expect(animeContents.folders.map((f) => f.folderPath), ['Anime/Naruto']);
      expect(animeContents.tracks, isEmpty);

      final narutoContents = scanner.getFolderContents('Anime/Naruto');
      expect(narutoContents.tracks, hasLength(1));
      expect(narutoContents.tracks.single.id, '1');
    });

    test('a loose track with no folder segment shows up in getRootTracks', () async {
      // "Anime" has no subfolders of its own here (its children map stays
      // empty), so it doesn't trigger the single-folder auto-flatten below —
      // that's covered separately.
      final scanner = LibraryScanner(apiWith([
        _song(id: '1', path: 'loose-track.mp3'),
        _song(id: '2', path: 'Anime/song.mp3'),
      ]));
      await scanner.scan();

      expect(scanner.getRootTracks().map((t) => t.id), ['1']);
    });

    test('a single top-level folder with subfolders is auto-flattened', () async {
      // Only one root folder ("Library") whose children get promoted to
      // top level, so the home screen doesn't show a redundant single entry.
      final scanner = LibraryScanner(apiWith([
        _song(id: '1', path: 'Library/Anime/song.mp3'),
        _song(id: '2', path: 'Library/Rock/song.mp3'),
      ]));
      await scanner.scan();

      final topLevel = scanner.getTopLevelFolders().map((f) => f.folderPath).toList();
      expect(topLevel, ['Library/Anime', 'Library/Rock']);
      expect(scanner.isFlattenedRoot('Library'), isTrue);
    });

    test('searchFolders matches on leaf name only, case-insensitively', () async {
      final scanner = LibraryScanner(apiWith([
        _song(id: '1', path: 'Anime/Naruto Shippuden/song.mp3'),
        _song(id: '2', path: 'Rock/Naruto Tribute Band/song.mp3'),
      ]));
      await scanner.scan();

      final results = scanner.searchFolders('naruto');
      expect(results, hasLength(2));
    });

    test('searchFolders returns nothing for a blank query', () async {
      final scanner = LibraryScanner(apiWith([_song(id: '1', path: 'A/song.mp3')]));
      await scanner.scan();

      expect(scanner.searchFolders('   '), isEmpty);
    });

    test('a scan failure with no prior data sets a fatal error, not a soft one', () async {
      final scanner = LibraryScanner(
        SubsonicApiService(
          serverUrl: 'https://navidrome.example.com',
          username: 'a',
          password: 'p',
          httpClient: MockClient((request) async => http.Response('boom', 500)),
        ),
      );

      await scanner.scan();

      expect(scanner.hasInitialData, isFalse);
      expect(scanner.error, isNotNull);
      expect(scanner.refreshError, isNull);
    });
  });

  group('resetAndClearCache', () {
    test('clears in-memory tracks and folder state', () async {
      final scanner = LibraryScanner(apiWith([
        _song(id: '1', path: 'Anime/Naruto/song.mp3'),
      ]));
      await scanner.scan();
      expect(scanner.allTracks, isNotEmpty);

      await scanner.resetAndClearCache();

      expect(scanner.allTracks, isEmpty);
      expect(scanner.hasInitialData, isFalse);
      expect(scanner.getTopLevelFolders(), isEmpty);
    });
  });
}
