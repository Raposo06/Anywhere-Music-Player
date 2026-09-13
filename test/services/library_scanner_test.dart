import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/services/library_cache.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import '../support/fake_gonic.dart';

Map<String, dynamic> _song({
  required String id,
  required String path,
  String? coverArtId,
}) => browseSong(
  id: id,
  path: path,
  coverArtId: coverArtId,
  artist: 'Some Artist',
  album: 'Some Album',
);

// Covers LibraryScanner: the cache-first, two-phase scan and what it reports
// around it. The cache is a MemoryLibraryCache — LibraryCache's in-memory
// adapter — so nothing here touches a filesystem or an isolate, and a test
// can put the cached entry either side of the freshness window by setting
// its scannedAt. The disk adapter has its own tests in library_cache_test.
void main() {
  late MemoryLibraryCache cache;

  setUp(() => cache = MemoryLibraryCache());

  SubsonicApiService apiWith(List<Map<String, dynamic>> songs) => SubsonicApiService(
    serverUrl: 'https://gonic.example.com',
    username: 'alice',
    password: 'secret',
    httpClient: gonicBrowseClient(songs),
  );

  LibraryScanner scannerWith(List<Map<String, dynamic>> songs) =>
      LibraryScanner(apiWith(songs), cache: cache);

  group('with no api connection', () {
    test('scan() sets a fatal error', () async {
      final scanner = LibraryScanner(null, cache: cache);

      await scanner.scan();

      expect(scanner.error, isNotNull);
      expect(scanner.hasInitialData, isFalse);
    });
  });

  group('scan()', () {
    test('walks the server tree and rebuilds it from the paths it descended', () async {
      final scanner = scannerWith(([
        _song(id: '1', path: 'Anime/Naruto/01 - Opening.mp3'),
        _song(id: '2', path: 'Rock/Album/02 - Song.mp3'),
      ]));

      await scanner.scan();

      expect(scanner.hasInitialData, isTrue);
      expect(scanner.error, isNull);
      expect(scanner.allTracks, hasLength(2));

      final topLevel = scanner.tree.topLevelFolders().map((f) => f.folderPath).toList();
      expect(topLevel, ['Anime', 'Rock']); // alphabetically sorted
    });

    test('populates folderName on scanned tracks (was left empty by the old inline parser)', () async {
      final scanner = scannerWith(([
        _song(id: '1', path: 'Anime/Naruto/01 - Opening.mp3'),
      ]));

      await scanner.scan();

      expect(scanner.allTracks.single.folderName, 'Naruto');
    });

    test('trackById returns the scanned copy, with its real path', () async {
      final scanner = scannerWith(([
        _song(id: '42', path: 'SOUNDTRACKS/Movies/HP/01 - Hedwig.flac'),
      ]));
      await scanner.scan();

      expect(scanner.tree.trackById('42')?.folderPath, 'SOUNDTRACKS/Movies/HP');
      expect(scanner.tree.trackById('nope'), isNull);
    });

    test('getFolderContents drills into a nested subfolder', () async {
      final scanner = scannerWith(([
        _song(id: '1', path: 'Anime/Naruto/01 - Opening.mp3'),
      ]));
      await scanner.scan();

      final animeContents = scanner.tree.contentsOf('Anime');
      expect(animeContents.folders.map((f) => f.folderPath), ['Anime/Naruto']);
      expect(animeContents.tracks, isEmpty);

      final narutoContents = scanner.tree.contentsOf('Anime/Naruto');
      expect(narutoContents.tracks, hasLength(1));
      expect(narutoContents.tracks.single.id, '1');
    });

    test('a loose track with no folder segment shows up in getRootTracks', () async {
      // "Anime" has no subfolders of its own here (its children map stays
      // empty), so it doesn't trigger the single-folder auto-flatten below —
      // that's covered separately.
      final scanner = scannerWith(([
        _song(id: '1', path: 'loose-track.mp3'),
        _song(id: '2', path: 'Anime/song.mp3'),
      ]));
      await scanner.scan();

      expect(scanner.tree.rootTracks().map((t) => t.id), ['1']);
    });

    test('a single top-level folder with subfolders is auto-flattened', () async {
      // Only one root folder ("Library") whose children get promoted to
      // top level, so the home screen doesn't show a redundant single entry.
      final scanner = scannerWith(([
        _song(id: '1', path: 'Library/Anime/song.mp3'),
        _song(id: '2', path: 'Library/Rock/song.mp3'),
      ]));
      await scanner.scan();

      final topLevel = scanner.tree.topLevelFolders().map((f) => f.folderPath).toList();
      expect(topLevel, ['Library/Anime', 'Library/Rock']);
      expect(scanner.tree.isFlattenedRoot('Library'), isTrue);
    });

    test('searchFolders matches on leaf name only, case-insensitively', () async {
      final scanner = scannerWith(([
        _song(id: '1', path: 'Anime/Naruto Shippuden/song.mp3'),
        _song(id: '2', path: 'Rock/Naruto Tribute Band/song.mp3'),
      ]));
      await scanner.scan();

      final results = scanner.tree.searchFolders('naruto');
      expect(results, hasLength(2));
    });

    test('searchFolders returns nothing for a blank query', () async {
      final scanner = scannerWith(([_song(id: '1', path: 'A/song.mp3')]));
      await scanner.scan();

      expect(scanner.tree.searchFolders('   '), isEmpty);
    });

    test('a scan failure with no prior data sets a fatal error, not a soft one', () async {
      final scanner = LibraryScanner(
        SubsonicApiService(
          serverUrl: 'https://gonic.example.com',
          username: 'a',
          password: 'p',
          httpClient: MockClient((request) async => http.Response('boom', 500)),
        ),
        cache: cache,
      );

      await scanner.scan();

      expect(scanner.hasInitialData, isFalse);
      expect(scanner.error, isNotNull);
      expect(scanner.notices.pending, isEmpty);
    });
  });

  group('cache freshness', () {
    /// scan() saves without awaiting (by design — see library_cache.dart),
    /// so give the save its microtask before reading the entry back.
    Future<void> waitForCache() async {
      await Future<void>.delayed(Duration.zero);
      expect(cache.entry, isNotNull, reason: 'cache was never written');
    }

    /// Restamp the cached entry to [age] ago, so a test can put it either
    /// side of LibraryScanner.cacheFreshFor without waiting.
    void ageCacheBy(Duration age) {
      cache.entry = (
        tracks: cache.entry!.tracks,
        scannedAt: DateTime.now().toUtc().subtract(age),
      );
    }

    test('a fresh cache renders from disk and skips the walk', () async {
      final songs = [_song(id: '1', path: 'Anime/song.mp3')];
      await scannerWith(songs).scan();
      await waitForCache();

      // The server gains a track. A launch inside the freshness window must
      // not see it — that's the whole point: no walk, no 200-odd requests.
      songs.add(_song(id: '2', path: 'Rock/song.mp3'));
      final second = scannerWith(songs);
      await second.scan();

      expect(second.allTracks.map((t) => t.id), ['1']);
      expect(second.hasInitialData, isTrue);
      expect(second.error, isNull);
    });

    test('a cache older than cacheFreshFor still walks the server', () async {
      final songs = [_song(id: '1', path: 'Anime/song.mp3')];
      await scannerWith(songs).scan();
      await waitForCache();
      ageCacheBy(LibraryScanner.cacheFreshFor + const Duration(minutes: 1));

      songs.add(_song(id: '2', path: 'Rock/song.mp3'));
      final second = scannerWith(songs);
      await second.scan();

      expect(second.allTracks.map((t) => t.id), unorderedEquals(['1', '2']));
    });

    test('a cache with no scannedAt stamp counts as stale', () async {
      final songs = [_song(id: '1', path: 'Anime/song.mp3')];
      await scannerWith(songs).scan();
      await waitForCache();
      cache.entry = (tracks: cache.entry!.tracks, scannedAt: null);

      songs.add(_song(id: '2', path: 'Rock/song.mp3'));
      final second = scannerWith(songs);
      await second.scan();

      expect(second.allTracks.map((t) => t.id), unorderedEquals(['1', '2']));
    });

    test('rescan() walks the server however fresh the cache is', () async {
      final songs = [_song(id: '1', path: 'Anime/song.mp3')];
      await scannerWith(songs).scan();
      await waitForCache();

      songs.add(_song(id: '2', path: 'Rock/song.mp3'));
      final second = scannerWith(songs);
      await second.rescan();

      expect(second.allTracks.map((t) => t.id), unorderedEquals(['1', '2']));
    });
  });

  group('resetAndClearCache', () {
    test('clears in-memory tracks and folder state', () async {
      final scanner = scannerWith(([
        _song(id: '1', path: 'Anime/Naruto/song.mp3'),
      ]));
      await scanner.scan();
      expect(scanner.allTracks, isNotEmpty);

      await scanner.resetAndClearCache();

      expect(scanner.allTracks, isEmpty);
      expect(scanner.hasInitialData, isFalse);
      expect(scanner.tree.topLevelFolders(), isEmpty);
      expect(cache.entry, isNull);
    });
  });
}
