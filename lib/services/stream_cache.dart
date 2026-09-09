import 'dart:async' show unawaited;
import 'dart:io' show Directory, File;

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// How a track's audio reaches the player: straight off the network, or via an
/// on-disk cache.
///
/// Android needs the cache — ExoPlayer can't seek the server's live HTTP stream
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

  /// Start pulling [track] down *before* anything asks to play it, so that when
  /// something does, the bytes are already local and playback starts without a
  /// round trip to the server.
  ///
  /// Best-effort and fire-and-forget: a failure here must never surface, since
  /// nothing is waiting on it and the ordinary load path still works. A cache
  /// that stores nothing has nothing to warm, so this is a no-op there.
  ///
  /// At most one track is held warm at a time. Prefetching a different one
  /// replaces the previous, which is what makes this safe to call on every
  /// track change.
  Future<void> prefetch(Track track, Uri uri, MediaItem tag);

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

  /// Nothing is stored, so there is nowhere to warm anything to.
  @override
  Future<void> prefetch(Track track, Uri uri, MediaItem tag) async {}

  @override
  Future<void> evict({required Track? keep}) async {}
}

/// Starts the background download for a prefetched source. See
/// [DiskStreamCache._warmer] for why this is injectable.
// ignore: experimental_member_use
typedef Warmer = Future<void> Function(LockCachingAudioSource source);

/// Android's on-disk stream cache. Each track streams into its own file under
/// `<temp>/audio_cache/<id>` — keyed by **track id, never the URL**, whose auth
/// salt rotates on every request and would otherwise guarantee a 100% miss.
/// Bounded by [_capBytes]; [evict] drops the oldest files after each load.
class DiskStreamCache extends StreamCache {
  DiskStreamCache({
    @visibleForTesting Directory? cacheDir,
    @visibleForTesting int? capBytes,
    @visibleForTesting Warmer? warmer,
  })  : _dir = cacheDir,
        _capBytes = capBytes ?? _defaultCapBytes,
        _warmer = warmer ?? _startDownload;

  /// What [prefetch] does to start the background download. Injectable for
  /// one reason: the real one cannot be run to completion in a test on any
  /// platform. `_fetch` renames an open `<id>.part` when it finishes, which
  /// Windows refuses, and interrupting it mid-flight (closing the test's
  /// server) errors it instead — either way the throw happens inside
  /// just_audio's own future, where no catch of ours can reach it, and lands
  /// on the test as an unhandled async error. Tests inject a no-op and assert
  /// the warm-slot bookkeeping, which is the part this class actually owns.
  final Warmer _warmer;

  // ignore: experimental_member_use
  static Future<void> _startDownload(LockCachingAudioSource source) =>
      // Asking for a single byte is what starts the download of the *whole*
      // file — see LockCachingAudioSource.request/_fetch.
      source.request(0, 1);

  static const int _defaultCapBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  final int _capBytes;

  Directory? _dir;

  // The one track held warm by [prefetch], and the source doing the warming.
  //
  // Kept so [sourceFor] can hand back the *same* instance rather than building
  // a second one for the same file. That is not an optimisation: two
  // LockCachingAudioSources over one cache file race a truncating `openWrite`
  // into `<id>.part` and corrupt it. Handing the warm instance over — and
  // clearing the slot as it goes — is what keeps exactly one alive per file.
  // ignore: experimental_member_use
  ({String id, LockCachingAudioSource source})? _warm;

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

  /// A source for [track] backed by its own file in [dir].
  ///
  /// The cache file is keyed by **track id, never the URL** — the URL's auth
  /// salt rotates on every request, so keying on it would guarantee a 100%
  /// miss (CLAUDE.md item 2). That decision is this one expression.
  ///
  /// `just_audio` marks this @experimental, but it is the only source type
  /// that gives ExoPlayer a seekable local file — see docs/decisions.md. One
  /// instance memoizes its own download, so re-passing it to setAudioSource on
  /// a retry just re-attaches the load already in flight. A *second* instance
  /// for the same file would race a truncating `openWrite` into `<id>.part`
  /// and corrupt the file being played — which is why callers reuse the
  /// instance instead of asking for another, and why [prefetch] hands its own
  /// over rather than letting [sourceFor] build a rival.
  // ignore: experimental_member_use
  static LockCachingAudioSource _open(
    Directory dir,
    Track track,
    Uri uri,
    MediaItem tag,
  ) =>
      // ignore: experimental_member_use
      LockCachingAudioSource(
        uri,
        tag: tag,
        cacheFile: File('${dir.path}/${track.id}'),
      );

  @override
  Future<AudioSource> sourceFor(Track track, Uri uri, MediaItem tag) async {
    // Already warm from a prefetch: take that instance rather than making a
    // rival for the same file. The download it started keeps running, and
    // whatever landed already is served from disk instead of the network.
    final warm = _takeWarm(track.id);
    if (warm != null) return warm;

    final dir = await _ensureDir();
    if (dir == null) return AudioSource.uri(uri, tag: tag);
    return _open(dir, track, uri, tag);
  }

  @override
  Future<void> prefetch(Track track, Uri uri, MediaItem tag) async {
    if (_warm?.id == track.id) return; // already warming this one
    final dir = await _ensureDir();
    if (dir == null) return;
    try {
      final source = _open(dir, track, uri, tag);
      _warm = (id: track.id, source: source);
      // Deliberately not awaited: the point is to return immediately and let
      // it fill in the background while the current track plays.
      unawaited(() async {
        try {
          await _warmer(source);
        } catch (e) {
          debugPrint('DiskStreamCache: prefetch failed for ${track.id}: $e');
          // Drop the slot so the ordinary load path builds a fresh source
          // rather than inheriting a half-dead one.
          if (_warm?.id == track.id) _warm = null;
        }
      }());
    } catch (e) {
      debugPrint('DiskStreamCache: could not prefetch ${track.id}: $e');
      _warm = null;
    }
  }

  /// The track [prefetch] is currently holding warm, or null. Test seam: the
  /// hand-over invariant (exactly one live source per cache file) is otherwise
  /// only observable as file corruption under a real player.
  @visibleForTesting
  String? get warmTrackId => _warm?.id;

  /// The source holding [warmTrackId] warm, or null. Test seam — see
  /// [warmTrackId].
  @visibleForTesting
  AudioSource? get warmSource => _warm?.source;

  /// Hand the warm source over for [trackId] and empty the slot, so only one
  /// instance is ever live for a given cache file.
  // ignore: experimental_member_use
  LockCachingAudioSource? _takeWarm(String trackId) {
    final warm = _warm;
    if (warm == null || warm.id != trackId) return null;
    _warm = null;
    return warm.source;
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
      // The warm track is protected alongside the playing one: eviction runs
      // after every load, and keeping only the current track would delete the
      // prefetch that load just started.
      final warmId = _warm?.id;
      bool isKept(File file) {
        final name = file.uri.pathSegments.last;
        for (final id in [keepId, warmId]) {
          if (id == null) continue;
          if (name == id || name.startsWith('$id.')) return true;
        }
        return false;
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
