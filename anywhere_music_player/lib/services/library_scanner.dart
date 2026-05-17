import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/folder.dart';
import 'subsonic_api_service.dart';
import 'library_cache.dart';

/// Scans the entire Navidrome library and builds a virtual folder tree
/// from the file paths of each track (e.g., "Anime/Naruto/song.mp3").
///
/// This recreates the filesystem-based browsing experience since Navidrome
/// only exposes tag-based (artist/album) browsing through its API.
class LibraryScanner with ChangeNotifier {
  final SubsonicApiService? _api;

  List<Track> _allTracks = [];
  Map<String, _FolderNode> _rootNodes = {};
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

  /// Cache-first scan. On cold start:
  ///   1. Load the on-disk cache (if any) and render it immediately.
  ///   2. Always kick off a fresh network scan in the background.
  ///   3. On success, overwrite both in-memory state and the cache.
  ///   4. On background failure with cache already shown, surface a soft
  ///      [refreshError] (snackbar) — keep showing the cached data.
  Future<void> scan() async {
    if (_isScanning) return;

    _isScanning = true;
    _error = null;
    _refreshError = null;
    notifyListeners();

    // ── Phase 1: hydrate from cache if we have no data yet ────────────────
    if (!_hasInitialData) {
      final cached = await LibraryCache.load();
      if (cached != null && cached.isNotEmpty) {
        debugPrint('LibraryScanner: hydrated ${cached.length} tracks from cache');
        _allTracks = cached;
        _buildFolderTree();
        _hasInitialData = true;
        notifyListeners();
      }
    }

    // ── Phase 2: always refetch from the network ──────────────────────────
    try {
      if (_api == null) {
        if (!_hasInitialData) _error = 'Not connected to server';
        return;
      }

      debugPrint('LibraryScanner: fetching all songs via Navidrome native API...');
      final rawSongs = await _api!.getAllSongsNativeApi();
      debugPrint('LibraryScanner: got ${rawSongs.length} songs from native API');

      final tracks = <Track>[];
      for (final song in rawSongs) {
        final songId = song['id']?.toString() ?? '';
        final coverArtId = song['coverArtId']?.toString() ?? song['id']?.toString();
        final path = song['path'] as String? ?? '';

        tracks.add(Track(
          id: songId,
          title: song['title'] as String? ?? 'Unknown',
          filename: path,
          streamUrl: _api!.buildStreamUrl(songId),
          coverArtUrl: coverArtId != null ? _api!.buildCoverArtUrl(coverArtId) : null,
          folderPath: path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '',
          durationSeconds: (song['duration'] is num) ? (song['duration'] as num).round() : null,
          fileSizeBytes: (song['size'] is num) ? (song['size'] as num).round() : null,
          createdAt: song['createdAt'] != null
              ? DateTime.tryParse(song['createdAt'] as String) ?? DateTime.now()
              : DateTime.now(),
          artist: song['artist'] as String?,
          album: song['album'] as String?,
        ));
      }

      _allTracks = tracks;
      _buildFolderTree();
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

  /// Force a rescan (network-only, ignores existing cache contents).
  /// Still updates the on-disk cache on success.
  Future<void> rescan() async {
    _allTracks = [];
    _rootNodes = {};
    _hasInitialData = false;
    _api?.clearCache();
    await scan();
  }

  /// Reset all in-memory state and delete the on-disk cache. Called from
  /// logout flows so the next login starts with a clean library.
  Future<void> resetAndClearCache() async {
    _allTracks = [];
    _rootNodes = {};
    _hasInitialData = false;
    _isScanning = false;
    _error = null;
    _refreshError = null;
    await LibraryCache.clear();
    notifyListeners();
  }

  /// Build the virtual folder tree from track file paths.
  void _buildFolderTree() {
    _rootNodes = {};

    for (final track in _allTracks) {
      // track.filename has the full path like "Anime/Naruto/23.Senya.mp3"
      final path = track.filename;
      final segments = path.split('/');

      if (segments.length < 2) {
        // Track is at root level, add to a special root node
        _rootNodes.putIfAbsent('', () => _FolderNode(name: '', fullPath: ''));
        _rootNodes['']!.tracks.add(track);
        continue;
      }

      // Walk the path segments (excluding the filename)
      var currentLevel = _rootNodes;
      var currentPath = '';

      for (var i = 0; i < segments.length - 1; i++) {
        final segment = segments[i];
        currentPath = currentPath.isEmpty ? segment : '$currentPath/$segment';

        if (!currentLevel.containsKey(segment)) {
          currentLevel[segment] = _FolderNode(name: segment, fullPath: currentPath);
        }

        final node = currentLevel[segment]!;

        if (i == segments.length - 2) {
          // Last folder segment — this is where the track lives
          node.tracks.add(track);
          // Use the first track's cover art as the folder's cover
          if (node.coverArtUrl == null && track.coverArtUrl != null) {
            node.coverArtUrl = track.coverArtUrl;
          }
        }

        currentLevel = node.children;
      }
    }
  }

  /// Get the effective root level of the folder tree.
  /// If there's only one top-level folder with no direct tracks,
  /// auto-flatten it and show its children instead.
  Map<String, _FolderNode> get _effectiveRoot {
    final nonEmpty = _rootNodes.entries.where((e) => e.key.isNotEmpty).toList();
    if (nonEmpty.length == 1) {
      final singleNode = nonEmpty.first.value;
      if (singleNode.children.isNotEmpty) {
        return singleNode.children;
      }
    }
    return _rootNodes;
  }

  /// Get the top-level folders from the virtual folder tree.
  List<Folder> getTopLevelFolders() {
    return _effectiveRoot.entries
        .where((e) => e.key.isNotEmpty)
        .map((e) => e.value.toFolder())
        .toList()
      ..sort((a, b) => a.folderPath.toLowerCase().compareTo(b.folderPath.toLowerCase()));
  }

  /// Get tracks that are at the root level (not in any folder).
  /// If the root was flattened, includes loose tracks from the skipped folder.
  List<Track> getRootTracks() {
    final nonEmpty = _rootNodes.entries.where((e) => e.key.isNotEmpty).toList();
    if (nonEmpty.length == 1 && nonEmpty.first.value.children.isNotEmpty) {
      // Root was flattened — return the skipped folder's direct tracks
      return nonEmpty.first.value.tracks;
    }
    return _rootNodes['']?.tracks ?? [];
  }

  /// Get the contents of a virtual folder by path.
  /// Returns subfolders and tracks at that path.
  ({List<Folder> folders, List<Track> tracks}) getFolderContents(String folderPath) {
    final node = _findNode(folderPath);
    if (node == null) {
      return (folders: <Folder>[], tracks: <Track>[]);
    }

    final subfolders = node.children.entries
        .where((e) => e.key.isNotEmpty)
        .map((e) => e.value.toFolder())
        .toList()
      ..sort((a, b) => a.folderPath.toLowerCase().compareTo(b.folderPath.toLowerCase()));

    return (folders: subfolders, tracks: node.tracks);
  }

  /// Get all tracks recursively under a folder path.
  List<Track> getAllTracksInFolder(String folderPath) {
    final node = _findNode(folderPath);
    return node?.allTracksRecursive() ?? [];
  }

  /// Navigate to a node by its full path, walking from _rootNodes.
  _FolderNode? _findNode(String folderPath) {
    final segments = folderPath.split('/');
    var currentLevel = _rootNodes;

    for (var i = 0; i < segments.length; i++) {
      final node = currentLevel[segments[i]];
      if (node == null) return null;
      if (i == segments.length - 1) return node;
      currentLevel = node.children;
    }

    return null;
  }
}

/// Internal tree node representing a folder in the virtual hierarchy.
class _FolderNode {
  final String name;
  final String fullPath;
  final Map<String, _FolderNode> children = {};
  final List<Track> tracks = [];
  String? coverArtUrl;

  _FolderNode({required this.name, required this.fullPath});

  /// Total track count including all nested subfolders.
  int get totalTrackCount {
    var count = tracks.length;
    for (final child in children.values) {
      count += child.totalTrackCount;
    }
    return count;
  }

  /// Number of direct child subfolders.
  int get subfolderCount => children.length;

  /// Get all tracks recursively (this folder + all subfolders).
  List<Track> allTracksRecursive() {
    final result = <Track>[...tracks];
    for (final child in children.values) {
      result.addAll(child.allTracksRecursive());
    }
    return result;
  }

  /// Convert to a Folder model for the UI.
  Folder toFolder() {
    return Folder(
      id: fullPath, // Use the path as ID for virtual folders
      folderPath: fullPath,
      trackCount: totalTrackCount,
      coverArtUrl: coverArtUrl ?? _findFirstCoverArt(),
      albumCount: subfolderCount,
    );
  }

  /// Find the first cover art URL from any track in this folder or subfolders.
  String? _findFirstCoverArt() {
    for (final track in tracks) {
      if (track.coverArtUrl != null) return track.coverArtUrl;
    }
    for (final child in children.values) {
      final url = child._findFirstCoverArt();
      if (url != null) return url;
    }
    return null;
  }
}
