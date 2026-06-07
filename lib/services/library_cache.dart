import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import 'subsonic_api_service.dart';

/// On-disk cache of the user's library. Stores a flat list of [Track]s as
/// JSON so the home screen can render instantly on cold start while a fresh
/// scan runs in the background.
///
/// Design notes:
/// - Single file per install. Wiped on logout (no per-account scoping).
/// - Atomic writes: serialize → write to `.tmp` → rename. Prevents a crash
///   mid-write from corrupting the cache.
/// - Self-healing on corruption: [load] catches parse errors, deletes the
///   bad file, and returns null so the caller falls through to a fresh scan.
class LibraryCache {
  static const _fileName  = 'library_cache.json';
  static const _tmpName   = 'library_cache.tmp';
  // Bumped to 2 when stream_url was dropped from the serialized schema. Old
  // v1 caches are discarded on load (they have a redundant stream_url field
  // that's now ignored, but version mismatch keeps the path clean).
  static const _version   = 2;

  /// Load the cached track list. Returns null when:
  ///   - the cache file doesn't exist (first launch / post-logout)
  ///   - the file is corrupt (parse error → file is deleted)
  ///   - the schema version doesn't match (file is deleted)
  ///
  /// JSON decode runs on a background isolate via [compute] — for a large
  /// library the cache file is several MB, and a synchronous decode on the
  /// main thread visibly stalls the first frame on cold start.
  static Future<List<Track>?> load({required SubsonicApiService api}) async {
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

      // Track.fromJson needs the live [api] (to recompute streamUrl), so
      // reconstruction stays on the main isolate. It's cheap compared to the
      // raw JSON decode.
      final rawTracks = decoded['tracks'] as List<dynamic>;
      return rawTracks
          .map((e) => Track.fromJson(e as Map<String, dynamic>, api: api))
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

  /// Persist [tracks] atomically. Errors are logged but never thrown — the
  /// cache is an optimization, not a source of truth.
  static Future<void> save(List<Track> tracks) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final tmp = File('${dir.path}${Platform.pathSeparator}$_tmpName');
      final target = File('${dir.path}${Platform.pathSeparator}$_fileName');

      final payload = {
        'version': _version,
        'scannedAt': DateTime.now().toUtc().toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(growable: false),
      };

      // Write to tmp, then rename. If the app dies between these calls, the
      // existing (stale-but-valid) cache remains.
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
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
