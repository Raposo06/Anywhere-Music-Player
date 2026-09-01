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
