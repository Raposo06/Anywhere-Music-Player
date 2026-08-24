import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

/// On-disk cache of the user's library. Stores a flat list of [Track]s as
/// JSON so the home screen can render instantly on cold start while a fresh
/// scan runs in the background.
///
/// Design notes:
/// - Single file per install. Wiped on logout (no per-account scoping).
/// - Crash-safe writes: serialize → write to `.tmp` → rename the previous
///   cache aside → rename `.tmp` into place → delete the old one. The
///   guarantee this actually gives: a crash never corrupts the cache, and
///   the sub-millisecond window between the two renames is observed (at
///   worst) as "no cache" — same as first launch, not corruption. See
///   [save] for why it isn't a plain delete-then-rename.
/// - Self-healing on corruption: [load] catches parse errors, deletes the
///   bad file, and returns null so the caller falls through to a fresh scan.
class LibraryCache {
  static const _fileName  = 'library_cache.json';
  static const _tmpName   = 'library_cache.tmp';
  static const _oldName   = 'library_cache.old';
  // Bumped to 2 when stream_url was dropped from the serialized schema, to
  // 3 when cover_art_url (a full URL with a live auth token+salt baked in)
  // was replaced by the bare cover_art_id — storing the resolved URL meant a
  // password-equivalent credential sat in this plaintext file until the next
  // scan overwrote it — and to 4 when the `filename` key was renamed to
  // `path` (Track.path; see Track.fromNativeApi). Old caches are discarded
  // on load (version mismatch) and rebuilt from a fresh scan.
  static const _version   = 4;

  /// Load the cached track list. Returns null when:
  ///   - the cache file doesn't exist (first launch / post-logout)
  ///   - the file is corrupt (parse error → file is deleted)
  ///   - the schema version doesn't match (file is deleted)
  ///
  /// JSON decode runs on a background isolate via [compute] — for a large
  /// library the cache file is several MB, and a synchronous decode on the
  /// main thread visibly stalls the first frame on cold start.
  static Future<List<Track>?> load() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;

      final raw = await file.readAsString();
      final decoded = await compute(_decodeCacheJson, raw);

      if (decoded == null) {
        // Parse failure on the isolate — treat as corrupt and self-heal.
        debugPrint('LibraryCache: isolate parse failed, discarding');
        await file.delete();
        return null;
      }
      if (decoded['version'] != _version) {
        debugPrint('LibraryCache: schema version mismatch, discarding');
        await file.delete();
        return null;
      }

      final rawTracks = decoded['tracks'] as List<dynamic>;
      return rawTracks
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('LibraryCache: failed to load, discarding cache: $e');
      try {
        final file = await _cacheFile();
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Persist [tracks] crash-safely (see the class doc for the exact
  /// guarantee — not strictly atomic, but never corrupting). Errors are
  /// logged but never thrown — the cache is an optimization, not a source
  /// of truth.
  static Future<void> save(List<Track> tracks) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final tmp = File('${dir.path}${Platform.pathSeparator}$_tmpName');
      final target = File('${dir.path}${Platform.pathSeparator}$_fileName');
      final old = File('${dir.path}${Platform.pathSeparator}$_oldName');

      final payload = {
        'version': _version,
        'scannedAt': DateTime.now().toUtc().toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(growable: false),
      };

      // JSON-encode on a background isolate — for a large library this
      // payload is several MB, and a synchronous encode on the main thread
      // stalls the UI right after every scan completes.
      final json = await compute(_encodeCacheJson, payload);

      // Write to tmp, then swap it into place. `File.rename` can't replace
      // an existing file on Windows, but deleting the target and then
      // renaming onto that exact path (the previous approach) hit a real
      // Windows race — a just-deleted path can briefly stay in a
      // pending-delete state, which surfaced during testing as
      // `PathAccessException: ... Access is denied`. Renaming the old file
      // aside instead of deleting it avoids reusing a path immediately
      // after removing something from it. At every step here, some file on
      // disk holds valid data: [target] until the first rename, [old]
      // between the two renames, [target] again after the second.
      await tmp.writeAsString(json, flush: true);
      if (await target.exists()) await target.rename(old.path);
      await tmp.rename(target.path);
      if (await old.exists()) await old.delete();
    } catch (e) {
      debugPrint('LibraryCache: failed to save: $e');
    }
  }

  /// Delete the cache file. Called on logout.
  static Future<void> clear() async {
    try {
      final file = await _cacheFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('LibraryCache: failed to clear: $e');
    }
  }

  static Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}

/// Isolate entry-point for the cache JSON decode. Top-level so [compute] can
/// send it across isolates. Returns null on any decode failure; the main
/// isolate handles deletion + fallback to a fresh scan.
Map<String, dynamic>? _decodeCacheJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}

/// Isolate entry-point for the cache JSON encode. Top-level so [compute] can
/// send it across isolates.
String _encodeCacheJson(Map<String, dynamic> payload) => jsonEncode(payload);
