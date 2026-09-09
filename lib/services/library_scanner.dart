import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/folder.dart';
import 'subsonic_api_service.dart';
import 'folder_tree.dart';
import 'folder_walk.dart';
import 'library_cache.dart';

/// Scans the entire library and holds the folder tree the UI browses
/// (e.g. "Anime/Naruto/song.mp3").
///
/// The scan walks the server's own directory tree (`FolderWalk.run`) and
/// keeps the flat list of tracks it returns; the tree here is rebuilt from
/// their paths so that a library hydrated from the on-disk cache — which
/// stores only that flat list — browses identically to a freshly scanned one.
class LibraryScanner with ChangeNotifier {
  final SubsonicApiService? _api;

  List<Track> _allTracks = [];
  FolderTree _tree = FolderTree.empty;
  bool _isScanning = false;
  bool _hasInitialData = false;
  String? _error;
  String? _refreshError;

  LibraryScanner(this._api);

  /// Whether this scanner has a valid API connection.
  bool get hasApi => _api != null;

  /// The api client this scanner was constructed with. Exposed so the
  /// provider layer can detect identity changes after logout/login and
  /// rebuild the scanner with the fresh client.
  SubsonicApiService? get api => _api;

  bool get isScanning => _isScanning;

  /// True once we have *any* library data to display — either from the
  /// on-disk cache or from a fresh scan. The UI uses this to decide whether
  /// to show the full-screen "Scanning library..." spinner.
  bool get hasInitialData => _hasInitialData;

  /// Fatal error from the initial load (no cache + scan failed). Blocks UI.
  String? get error => _error;

  /// Soft error from a background refresh when cached data is already shown.
  /// UI should surface this as a snackbar then clear it via
  /// [clearRefreshError]. Doesn't block browsing.
  String? get refreshError => _refreshError;

  List<Track> get allTracks => _allTracks;

  void clearRefreshError() {
    if (_refreshError == null) return;
    _refreshError = null;
    notifyListeners();
  }

  /// How long a cache read counts as fresh. Inside this window a cold start
  /// renders from disk and stops there — no phase 2 — because the walk costs
  /// one request per directory (a few hundred, several seconds) and a music
  /// library rarely changes between launches. Outside it, or on an explicit
  /// [rescan], the network scan runs as before. Pull-to-refresh (phone) and
  /// the header refresh button (desktop) are the escape hatch for "I just
  /// added an album and want it now".
  static const Duration cacheFreshFor = Duration(hours: 6);

  /// Cache-first scan. On cold start:
  ///   1. Load the on-disk cache (if any) and render it immediately.
  ///   2. If that cache is younger than [cacheFreshFor] and [force] is not
  ///      set, stop there — the rendered data is current enough.
  ///   3. Otherwise refetch from the network in the background.
  ///   4. On success, overwrite both in-memory state and the cache.
  ///   5. On background failure with cache already shown, surface a soft
  ///      [refreshError] (snackbar) — keep showing the cached data.
  ///
  /// [force] skips the freshness check only; the cache is still read first so
  /// something stays on screen while the network scan runs.
  Future<void> scan({bool force = false}) async {
    if (_isScanning) return;

    _isScanning = true;
    _error = null;
    _refreshError = null;
    notifyListeners();

    try {
      // Nothing below works logged out, and there's nothing to play anyway.
      if (_api == null) {
        if (!_hasInitialData) _error = 'Not connected to server';
        return;
      }

      // ── Phase 1: hydrate from cache if we have no data yet ──────────────
      // Loading the cache no longer needs a live api client (stream/cover URLs
      // are resolved at the point of use, not recomputed here).
      if (!_hasInitialData) {
        final cached = await LibraryCache.loadEntry();
        if (cached != null && cached.tracks.isNotEmpty) {
          debugPrint(
              'LibraryScanner: hydrated ${cached.tracks.length} tracks from cache');
          _allTracks = cached.tracks;
          _tree = FolderTree.from(_allTracks);
          _hasInitialData = true;
          notifyListeners();

          if (!force && _isFresh(cached.scannedAt)) {
            debugPrint('LibraryScanner: cache is fresh, skipping the walk');
            return;
          }
        }
      }

      // ── Phase 2: refetch from the network ───────────────────────────────
      debugPrint('LibraryScanner: walking the server folder tree...');
      // One request per directory now, so a large library is a long scan.
      // Logged at the same 500-song cadence the old paged fetch used — enough
      // to tell a slow scan from a stalled one without thousands of lines.
      var lastLogged = 0;
      final tracks = await FolderWalk(_api).run(
        onProgress: (songsSoFar) {
          if (songsSoFar - lastLogged < 500) return;
          lastLogged = songsSoFar;
          debugPrint('LibraryScanner: $songsSoFar songs so far...');
        },
      );
      debugPrint('LibraryScanner: got ${tracks.length} songs from the walk');

      _allTracks = tracks;
      _tree = FolderTree.from(_allTracks);
      _hasInitialData = true;

      // Persist for the next cold start. Fire-and-forget; failures don't
      // affect the user-visible state.
      unawaited(LibraryCache.save(tracks));
    } catch (e) {
      debugPrint('LibraryScanner: error scanning library: $e');
      if (_hasInitialData) {
        // We already rendered cached data; degrade gracefully.
        _refreshError = "Couldn't refresh library — showing offline data";
      } else {
        _error = 'Failed to scan library: $e';
      }
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Whether a cache written at [scannedAt] is still inside [cacheFreshFor].
  /// A missing stamp (old cache file, unparseable value) and a stamp in the
  /// future (clock skew) both count as stale — the failure mode of scanning
  /// when we needn't is a slow launch; the other way round is a wrong library.
  static bool _isFresh(DateTime? scannedAt) {
    if (scannedAt == null) return false;
    final age = DateTime.now().toUtc().difference(scannedAt);
    return !age.isNegative && age < cacheFreshFor;
  }

  /// Force a rescan. Always hits the network, however fresh the cache is —
  /// this is the user asking for the library they can see on the server right
  /// now. Still updates the on-disk cache on success.
  Future<void> rescan() async {
    _allTracks = [];
    _tree = FolderTree.empty;
    _hasInitialData = false;
    await scan(force: true);
  }

  /// Reset all in-memory state and delete the on-disk cache. Called from
  /// logout flows so the next login starts with a clean library.
  Future<void> resetAndClearCache() async {
    _allTracks = [];
    _tree = FolderTree.empty;
    _hasInitialData = false;
    _isScanning = false;
    _error = null;
    _refreshError = null;
    await LibraryCache.clear();
    notifyListeners();
  }

  /// The browsable tree built from [allTracks]. Prefer this over the
  /// forwarders below in new code; they exist so the screens didn't all have
  /// to change at once.
  FolderTree get tree => _tree;

  /// The scanned copy of [id] — the one carrying a real library path — or
  /// null. Lets a track that arrived by another route (a playlist fetch,
  /// whose paths are tag-based) be resolved back to its canonical form.
  Track? trackById(String id) => _tree.trackById(id);
  bool isFlattenedRoot(String folderPath) => _tree.isFlattenedRoot(folderPath);
  List<Folder> getTopLevelFolders() => _tree.topLevelFolders();
  List<Track> getRootTracks() => _tree.rootTracks();
  ({List<Folder> folders, List<Track> tracks}) getFolderContents(
    String folderPath,
  ) => _tree.contentsOf(folderPath);
  List<Track> getAllTracksInFolder(String folderPath) =>
      _tree.allTracksUnder(folderPath);
  List<Folder> searchFolders(String query) => _tree.searchFolders(query);
}
