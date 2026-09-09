import 'dart:io';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:anywhere_music_player/services/stream_cache.dart';
import '../support/fixtures.dart';

// StreamCache carries the on-disk stream cache that used to live inside
// AudioPlayerService — including the LRU-with-sidecar-protection eviction rule
// that had no test because it sat behind a live ExoPlayer. It runs on any
// platform here: evict() is plain file I/O over a directory the test provides.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('stream_cache_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Writes a [bytes]-byte file named [name] and back-dates it by [ageMinutes]
  /// so eviction order is predictable.
  File write(String name, int bytes, {int ageMinutes = 0}) {
    final f = File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 0));
    final when = DateTime.now().subtract(Duration(minutes: ageMinutes));
    f.setLastModifiedSync(when);
    return f;
  }

  Set<String> remaining() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toSet();

  group('DiskStreamCache.prefetch', () {
    // No loopback server and no real download. DiskStreamCache takes a
    // `warmer` seam precisely so these can't run one: just_audio's _fetch
    // renames an open `<id>.part` when it completes (Windows refuses) and
    // errors if interrupted (what happens when a test's server is torn down
    // mid-flight), and either throw lands inside its own future as an
    // unhandled async error blamed on an already-finished test. That was
    // green on Windows and red on the Linux runner purely on timing.
    //
    // What is left is what this class actually owns: which track is held
    // warm, and that the warm source is handed over rather than duplicated.
    const tag = MediaItem(id: '1', title: 'Sample');
    final uri = Uri.parse('http://127.0.0.1:1/song');

    /// A cache whose prefetch starts no download. [started] records the
    /// sources it would have warmed, so a test can still tell that prefetch
    /// got as far as kicking one off.
    DiskStreamCache cacheWithNoDownload(List<AudioSource> started) =>
        DiskStreamCache(
          cacheDir: dir,
          warmer: (source) async => started.add(source),
        );

    test('holds the prefetched track warm, and starts its download', () async {
      final started = <AudioSource>[];
      final cache = cacheWithNoDownload(started);

      await cache.prefetch(sampleTrack(id: 'warm'), uri, tag);

      expect(cache.warmTrackId, 'warm');
      expect(cache.warmSource, isNotNull);
      expect(started, [same(cache.warmSource)]);
    });

    test('hands the warm source to sourceFor rather than building a rival', () async {
      // Two LockCachingAudioSources over one cache file race a truncating
      // write into `<id>.part`. The hand-over is what stops that, so it is the
      // property worth pinning.
      final cache = cacheWithNoDownload([]);
      final track = sampleTrack(id: 'warm');
      await cache.prefetch(track, uri, tag);
      final warmed = cache.warmSource;

      final source = await cache.sourceFor(track, uri, tag);

      expect(identical(source, warmed), isTrue);
      // ...and the slot is empty afterwards, so a later load can't be handed
      // the same instance a second time.
      expect(cache.warmTrackId, isNull);
      expect(cache.warmSource, isNull);
    });

    test('a track that was never warmed gets its own source', () async {
      final cache = cacheWithNoDownload([]);
      await cache.prefetch(sampleTrack(id: 'warm'), uri, tag);
      final warmed = cache.warmSource;

      final other = await cache.sourceFor(sampleTrack(id: 'other'), uri, tag);

      expect(identical(other, warmed), isFalse);
      // The warm slot is untouched — a different track playing must not throw
      // away the prefetch.
      expect(cache.warmTrackId, 'warm');
    });

    test('re-prefetching the same track keeps the download already running', () async {
      final started = <AudioSource>[];
      final cache = cacheWithNoDownload(started);
      final track = sampleTrack(id: 'warm');
      await cache.prefetch(track, uri, tag);
      final first = cache.warmSource;

      await cache.prefetch(track, uri, tag);

      expect(identical(cache.warmSource, first), isTrue);
      // ...and no second download was kicked off for the same file.
      expect(started, hasLength(1));
    });

    test('a failed download drops the warm slot rather than keeping a dead source', () async {
      // The ordinary load path must build a fresh source, not inherit a
      // half-dead one — so the slot has to clear itself when the fetch throws.
      final cache = DiskStreamCache(
        cacheDir: dir,
        warmer: (_) async => throw const SocketException('refused'),
      );

      await cache.prefetch(sampleTrack(id: 'warm'), uri, tag);
      await pumpEventQueue();

      expect(cache.warmTrackId, isNull);
      expect(cache.warmSource, isNull);
    });

    test('eviction spares the warm track, not just the playing one', () async {
      // evict() runs after every load, and the load is what starts the
      // prefetch — so protecting only the current track would delete the file
      // that load just began filling.
      final cache = DiskStreamCache(
        cacheDir: dir,
        capBytes: 100,
        warmer: (_) async {},
      );
      await cache.prefetch(sampleTrack(id: 'warm'), uri, tag);
      write('warm', 40, ageMinutes: 99);
      write('warm.part', 10, ageMinutes: 99);
      write('playing', 40, ageMinutes: 50);
      write('cold', 40, ageMinutes: 10);

      await cache.evict(keep: sampleTrack(id: 'playing'));

      expect(remaining(), containsAll(<String>{'warm', 'warm.part', 'playing'}));
      expect(remaining(), isNot(contains('cold')));
    });
  });

  group('DiskStreamCache.evict', () {
    test('does nothing while under the cap', () async {
      write('a', 40, ageMinutes: 30);
      write('b', 40, ageMinutes: 10);

      await DiskStreamCache(cacheDir: dir, capBytes: 100).evict(keep: null);

      expect(remaining(), {'a', 'b'});
    });

    test('drops the oldest files first until back under the cap', () async {
      write('old', 40, ageMinutes: 50);
      write('mid', 40, ageMinutes: 30);
      write('new', 40, ageMinutes: 10);

      await DiskStreamCache(cacheDir: dir, capBytes: 100).evict(keep: null);

      // 120 bytes > 100: dropping the oldest (40) leaves 80, under the cap.
      expect(remaining(), {'mid', 'new'});
    });

    test('never evicts the kept track, even when it is the oldest', () async {
      write('keepme', 40, ageMinutes: 99);
      write('other', 40, ageMinutes: 30);
      write('newest', 40, ageMinutes: 1);

      await DiskStreamCache(cacheDir: dir, capBytes: 100)
          .evict(keep: sampleTrack(id: 'keepme'));

      // The oldest is protected, so the next-oldest ('other') goes instead.
      expect(remaining(), {'keepme', 'newest'});
    });

    test('protects the kept track\'s .part and .mime sidecars', () async {
      write('cur', 20, ageMinutes: 99);
      write('cur.part', 20, ageMinutes: 99);
      write('cur.mime', 20, ageMinutes: 99);
      write('filler', 60, ageMinutes: 1);

      await DiskStreamCache(cacheDir: dir, capBytes: 50)
          .evict(keep: sampleTrack(id: 'cur'));

      // 120 > 50, but the only unprotected file is 'filler'; dropping it
      // leaves 60 — still over, and eviction stops rather than touch 'cur*'.
      expect(remaining(), {'cur', 'cur.part', 'cur.mime'});
    });

    test('is a no-op when the cache directory was never created', () async {
      await DiskStreamCache(capBytes: 100).evict(keep: null);
      // No throw, nothing to assert beyond that.
    });
  });

  group('DirectStreamCache', () {
    test('hands back a plain network source and evicts nothing', () async {
      const cache = DirectStreamCache();
      final source = await cache.sourceFor(
        sampleTrack(id: '1'),
        Uri.parse('https://example.test/stream?id=1'),
        const MediaItem(id: '1', title: 'x'),
      );

      expect(source, isA<UriAudioSource>());
      await cache.evict(keep: null); // no throw
    });
  });
}
