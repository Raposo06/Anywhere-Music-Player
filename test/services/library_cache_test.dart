import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:anywhere_music_player/services/library_cache.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import 'package:anywhere_music_player/models/track.dart';
import '../support/fake_path_provider.dart';

void main() {
  final api = SubsonicApiService(
    serverUrl: 'https://navidrome.example.com',
    username: 'alice',
    password: 'secret',
  );

  late Directory tempDir;

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
    filename: 'f$id.mp3',
    streamUrl: 'https://x/stream',
    folderPath: '',
    createdAt: DateTime(2024),
  );

  test('load returns null when no cache file exists (first launch)', () async {
    expect(await LibraryCache.load(api: api), isNull);
  });

  test('save then load round-trips the track list', () async {
    final tracks = [track('1'), track('2'), track('3')];

    await LibraryCache.save(tracks);
    final loaded = await LibraryCache.load(api: api);

    expect(loaded, isNotNull);
    expect(loaded!.map((t) => t.id), ['1', '2', '3']);
    expect(loaded.map((t) => t.title), ['Track 1', 'Track 2', 'Track 3']);
  });

  test('save writes atomically: no leftover .tmp file after a successful save', () async {
    await LibraryCache.save([track('1')]);

    final tmp = File('${tempDir.path}${Platform.pathSeparator}library_cache.tmp');
    expect(await tmp.exists(), isFalse);
  });

  test('load self-heals a corrupt cache file: deletes it and returns null', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}library_cache.json');
    await file.writeAsString('not valid json{{{');

    final loaded = await LibraryCache.load(api: api);

    expect(loaded, isNull);
    expect(await file.exists(), isFalse);
  });

  test('load discards a cache written under an older schema version', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}library_cache.json');
    await file.writeAsString(jsonEncode({
      'version': 2, // current schema is 3 — see docs/decisions.md
      'tracks': [track('1').toJson()],
    }));

    final loaded = await LibraryCache.load(api: api);

    expect(loaded, isNull);
    expect(await file.exists(), isFalse);
  });

  test('clear deletes the cache file', () async {
    await LibraryCache.save([track('1')]);
    await LibraryCache.clear();

    expect(await LibraryCache.load(api: api), isNull);
  });

  test('clear is a no-op (does not throw) when there is no cache file', () async {
    await expectLater(LibraryCache.clear(), completes);
  });

  test('the persisted JSON never contains a resolved cover art URL (security)', () async {
    final withCover = Track(
      id: '1',
      title: 'T',
      filename: 'f.mp3',
      streamUrl: 'https://x/stream',
      coverArtUrl: 'https://x/rest/getCoverArt?id=cov-1&u=alice&t=deadbeef&s=salt',
      coverArtId: 'cov-1',
      folderPath: '',
      createdAt: DateTime(2024),
    );

    await LibraryCache.save([withCover]);

    final raw = await File(
      '${tempDir.path}${Platform.pathSeparator}library_cache.json',
    ).readAsString();

    expect(raw, isNot(contains('deadbeef'))); // no live auth token on disk
    expect(raw, isNot(contains('cover_art_url')));
    expect(raw, contains('cov-1')); // the bare id is fine
  });
}
