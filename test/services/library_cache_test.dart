import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:anywhere_music_player/services/library_cache.dart';
import 'package:anywhere_music_player/models/track.dart';
import '../support/fake_path_provider.dart';

// Covers DiskLibraryCache — the on-disk adapter, against a temp directory
// via FakePathProviderPlatform. The seam it implements (LibraryCache) has an
// in-memory adapter too; LibraryScanner's tests use that one, so this file
// is the only one that needs a filesystem.
void main() {
  late Directory tempDir;
  const cache = DiskLibraryCache();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library_cache_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Track track(String id) => Track(
    id: id,
    title: 'Track $id',
    path: 'f$id.mp3',
    folderPath: '',
    createdAt: DateTime(2024),
  );

  test('load returns null when no cache file exists (first launch)', () async {
    expect(await cache.load(), isNull);
  });

  test('save then load round-trips the track list', () async {
    final tracks = [track('1'), track('2'), track('3')];

    await cache.save(tracks);
    final loaded = (await cache.load())?.tracks;

    expect(loaded, isNotNull);
    expect(loaded!.map((t) => t.id), ['1', '2', '3']);
    expect(loaded.map((t) => t.title), ['Track 1', 'Track 2', 'Track 3']);
  });

  test('save writes atomically: no leftover .tmp or .old file after a successful save', () async {
    await cache.save([track('1')]);

    final tmp = File('${tempDir.path}${Platform.pathSeparator}library_cache.tmp');
    final old = File('${tempDir.path}${Platform.pathSeparator}library_cache.old');
    expect(await tmp.exists(), isFalse);
    expect(await old.exists(), isFalse);
  });

  test('save over an existing cache does not throw (T2 regression)', () async {
    // The bug: save() used to delete the target then rename .tmp onto that
    // same path, which on Windows can throw PathAccessException ("Access is
    // denied") because a just-deleted path can briefly stay in a
    // pending-delete state. This is exactly the second-save scenario, where
    // a real cache file already sits at the target path.
    await cache.save([track('1')]);
    await cache.save([track('1'), track('2')]);

    final loaded = (await cache.load())?.tracks;
    expect(loaded!.map((t) => t.id), ['1', '2']);
  });

  test('a crash between the two renames degrades to "no cache", not corruption', () async {
    // Simulates the narrow window inside save() where the previous cache has
    // been renamed to .old but the new one hasn't landed at the target path
    // yet. load() must not throw — it should behave exactly like first
    // launch (a fresh scan rebuilds it), which is the guarantee the class
    // doc promises.
    await File('${tempDir.path}${Platform.pathSeparator}library_cache.old')
        .writeAsString(jsonEncode({
          'version': 4,
          'tracks': [track('1').toJson()],
        }));

    expect(await cache.load(), isNull);
  });

  test('load self-heals a corrupt cache file: deletes it and returns null', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}library_cache.json');
    await file.writeAsString('not valid json{{{');

    final loaded = await cache.load();

    expect(loaded, isNull);
    expect(await file.exists(), isFalse);
  });

  test('load discards a cache written under an older schema version', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}library_cache.json');
    await file.writeAsString(jsonEncode({
      'version': 3, // any version below the current one — see docs/decisions.md
      'tracks': [track('1').toJson()],
    }));

    final loaded = await cache.load();

    expect(loaded, isNull);
    expect(await file.exists(), isFalse);
  });

  test('load returns when the scan that wrote the cache ran', () async {
    final before = DateTime.now().toUtc();
    await cache.save([track('1')]);

    final entry = await cache.load();

    expect(entry, isNotNull);
    expect(entry!.tracks.map((t) => t.id), ['1']);
    expect(entry.scannedAt, isNotNull);
    // Within the window this test itself spans, and in UTC — LibraryScanner
    // subtracts it from a UTC now to decide whether to skip the walk, so a
    // local-time stamp would come out hours off.
    expect(entry.scannedAt!.isUtc, isTrue);
    expect(
      entry.scannedAt!.isBefore(before.subtract(const Duration(seconds: 1))),
      isFalse,
    );
  });

  test('load reports a missing scannedAt as null, not a throw', () async {
    // A cache file written by a build that predates the stamp, or one whose
    // stamp got mangled. The caller reads null as "age unknown" and rescans.
    final file = File('${tempDir.path}${Platform.pathSeparator}library_cache.json');
    await cache.save([track('1')]);
    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    decoded['scannedAt'] = 'not a date';
    await file.writeAsString(jsonEncode(decoded));

    final entry = await cache.load();

    expect(entry, isNotNull);
    expect(entry!.tracks, hasLength(1));
    expect(entry.scannedAt, isNull);
  });

  test('clear deletes the cache file', () async {
    await cache.save([track('1')]);
    await cache.clear();

    expect(await cache.load(), isNull);
  });

  test('clear is a no-op (does not throw) when there is no cache file', () async {
    await expectLater(cache.clear(), completes);
  });

  test('the persisted JSON stores only the cover art id, never a URL (security)', () async {
    // Track no longer has a coverArtUrl field at all (see StreamUrlResolver,
    // docs/reviews/2026-08-22-architecture-review.html Candidate 07) — so
    // there's no live auth token to leak here even in principle. This pins
    // the JSON shape so a future change can't quietly reintroduce one.
    final withCover = Track(
      id: '1',
      title: 'T',
      path: 'f.mp3',
      coverArtId: 'cov-1',
      folderPath: '',
      createdAt: DateTime(2024),
    );

    await cache.save([withCover]);

    final raw = await File(
      '${tempDir.path}${Platform.pathSeparator}library_cache.json',
    ).readAsString();

    expect(raw, isNot(contains('cover_art_url')));
    expect(raw, isNot(contains('stream_url')));
    expect(raw, contains('cov-1')); // the bare id is fine
  });
}
