import 'dart:io' show Directory, File;

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// How a track's audio reaches the player: straight off the network, or via an
/// on-disk cache.
///
/// Android needs the cache — ExoPlayer can't seek Navidrome's live HTTP stream
/// for VBR MP3 / FLAC / OGG, and `LockCachingAudioSource` hands it a seekable
/// local file that also survives a replay without re-fetching. Desktop
/// (media_kit) and web seek the network stream directly and use
/// [DirectStreamCache]. The platform picks one in `main()`, next to the other
/// platform wiring; nothing else in playback needs to know which.
abstract class StreamCache {
  const StreamCache();

  /// The source to hand `just_audio` for [track], given a freshly-minted stream
  /// [uri] and the OS-media-notification [tag].
  ///
  /// Callers must reuse the returned instance across a `setAudioSource` retry
  /// rather than asking for a second one for the same track — see
  /// [DiskStreamCache] for why.
  Future<AudioSource> sourceFor(Track track, Uri uri, MediaItem tag);

  /// Trim the cache back under budget, keeping [keep]'s files. Best-effort and
  /// fire-and-forget; a no-op for a cache that stores nothing.
  Future<void> evict({required Track? keep});
}

/// No cache: the player streams straight from the network. Desktop, web, tests.
class DirectStreamCache extends StreamCache {
  const DirectStreamCache();

  @override
  Future<AudioSource> sourceFor(Track track, Uri uri, MediaItem tag) async =>
      AudioSource.uri(uri, tag: tag);

  @override
  Future<void> evict({required Track? keep}) async {}
}

/// Android's on-disk stream cache. Each track streams into its own file under
/// `<temp>/audio_cache/<id>` — keyed by **track id, never the URL**, whose auth
/// salt rotates on every request and would otherwise guarantee a 100% miss.
/// Bounded by [_capBytes]; [evict] drops the oldest files after each load.
class DiskStreamCache extends StreamCache {
  DiskStreamCache({
    @visibleForTesting Directory? cacheDir,
    @visibleForTesting int? capBytes,
  })  : _dir = cacheDir,
        _capBytes = capBytes ?? _defaultCapBytes;

  static const int _defaultCapBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  final int _capBytes;

  Directory? _dir;

  Future<Directory?> _ensureDir() async {
    if (_dir != null) return _dir;
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/audio_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      _dir = dir;
    } catch (e) {
      debugPrint('DiskStreamCache: could not init cache dir: $e');
    }
    return _dir;
  }

  @override
  Future<AudioSource> sourceFor(Track track, Uri uri, MediaItem tag) async {
    final dir = await _ensureDir();
    if (dir == null) return AudioSource.uri(uri, tag: tag);
    // `just_audio` marks this @experimental, but it is the only source type
    // that gives ExoPlayer a seekable local file — see docs/decisions.md. One
    // instance memoizes its own download, so re-passing it to setAudioSource on
    // a retry just re-attaches the load already in flight. A *second* instance
    // for the same file would race a truncating `openWrite` into `<id>.part`
    // and corrupt the file being played — which is why callers reuse the
    // instance instead of asking for another.
    // ignore: experimental_member_use
    return LockCachingAudioSource(
      uri,
      tag: tag,
      cacheFile: File('${dir.path}/${track.id}'),
    );
  }

  @override
  Future<void> evict({required Track? keep}) async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final entries = <({File file, int size, DateTime modified})>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final st = await e.stat();
        total += st.size;
        entries.add((file: e, size: st.size, modified: st.modified));
      }
      if (total <= _capBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified)); // oldest first
      final keepId = keep?.id;
      // Protects the kept song's cache file *and* the `.part` / `.mime`
      // sidecars LockCachingAudioSource writes beside it while downloading —
      // matching only the exact id would evict a half-written `<id>.part` out
      // from under the stream currently playing.
      bool isKept(File file) {
        if (keepId == null) return false;
        final name = file.uri.pathSegments.last;
        return name == keepId || name.startsWith('$keepId.');
      }

      for (final entry in entries) {
        if (total <= _capBytes) break;
        if (isKept(entry.file)) continue;
        try {
          await entry.file.delete();
          total -= entry.size;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('DiskStreamCache: eviction failed: $e');
    }
  }
}
