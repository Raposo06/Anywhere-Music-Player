import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/folder.dart';
import 'subsonic_api_service.dart';

/// Scans the entire Navidrome library and builds a virtual folder tree
/// from the file paths of each track (e.g., "Anime/Naruto/song.mp3").
///
/// This recreates the filesystem-based browsing experience since Navidrome
/// only exposes tag-based (artist/album) browsing through its API.
class LibraryScanner with ChangeNotifier {
  final SubsonicApiService _api;

  List<Track> _allTracks = [];
  Map<String, _FolderNode> _rootNodes = {};
  bool _isScanning = false;
  bool _hasScanned = false;
  String? _error;

  LibraryScanner(this._api);

  bool get isScanning => _isScanning;
  bool get hasScanned => _hasScanned;
  String? get error => _error;
  List<Track> get allTracks => _allTracks;

  /// Scan the entire library by walking the artist/album tree.
  /// Collects all tracks and builds the folder hierarchy from file paths.
  Future<void> scan() async {
    if (_isScanning) return;
    if (_hasScanned) return; // Already scanned this session

    _isScanning = true;
    _error = null;
    notifyListeners();

    try {
      final tracks = <Track>[];

      // Step 1: Get all artists from getIndexes
      final indexData = await _api.getIndexes();
      final indexes = indexData['indexes'] as Map<String, dynamic>?;

      if (indexes == null) {
        _isScanning = false;
        _hasScanned = true;
        notifyListeners();
        return;
      }

      final indexList = indexes['index'];
      if (indexList == null) {
        _isScanning = false;
        _hasScanned = true;
        notifyListeners();
        return;
      }

      // Collect all artist IDs
      final artistIds = <String>[];
      final items = indexList is List ? indexList : [indexList];
      for (final index in items) {
        final artistList = index['artist'];
        if (artistList == null) continue;
        final artists = artistList is List ? artistList : [artistList];
        for (final artist in artists) {
          final id = (artist as Map<String, dynamic>)['id']?.toString();
          if (id != null) artistIds.add(id);
        }
      }

      debugPrint('LibraryScanner: Found ${artistIds.length} artists, scanning...');

      // Step 2: Fetch all artist directories in parallel (batched)
      const batchSize = 20;
      for (var i = 0; i < artistIds.length; i += batchSize) {
        final batch = artistIds.skip(i).take(batchSize);
        final results = await Future.wait(
          batch.map((id) => _fetchTracksRecursive(id)),
        );
        for (final trackList in results) {
          tracks.addAll(trackList);
        }
      }

      debugPrint('LibraryScanner: Scanned ${tracks.length} total tracks');
      for (final t in tracks.take(20)) {
        debugPrint('LibraryScanner: path="${t.filename}" title="${t.title}"');
      }
      if (tracks.length > 20) {
        debugPrint('LibraryScanner: ... and ${tracks.length - 20} more');
      }

      _allTracks = tracks;
      _buildFolderTree();
      final topFolders = getTopLevelFolders();
      debugPrint('LibraryScanner: Built ${topFolders.length} top-level folders: ${topFolders.map((f) => f.folderPath).join(', ')}');
      _hasScanned = true;
    } catch (e) {
      debugPrint('LibraryScanner: Error scanning library: $e');
      _error = 'Failed to scan library: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Force a rescan (clears cache).
  Future<void> rescan() async {
    _hasScanned = false;
    _allTracks = [];
    _rootNodes = {};
    _api.clearCache();
    await scan();
  }

  /// Recursively fetch all tracks under a directory ID.
  Future<List<Track>> _fetchTracksRecursive(String directoryId) async {
    try {
      final contents = await _api.getDirectoryContents(directoryId);
      final tracks = <Track>[...contents.tracks];

      if (contents.folders.isNotEmpty) {
        final subResults = await Future.wait(
          contents.folders
              .where((f) => f.id != null)
              .map((f) => _fetchTracksRecursive(f.id!)),
        );
        for (final subTracks in subResults) {
          tracks.addAll(subTracks);
        }
      }

      return tracks;
    } catch (e) {
      debugPrint('LibraryScanner: Error fetching directory $directoryId: $e');
      return [];
    }
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

  /// Get the top-level folders from the virtual folder tree.
  List<Folder> getTopLevelFolders() {
    return _rootNodes.entries
        .where((e) => e.key.isNotEmpty) // Exclude root-level tracks node
        .map((e) => e.value.toFolder())
        .toList()
      ..sort((a, b) => a.folderPath.toLowerCase().compareTo(b.folderPath.toLowerCase()));
  }

  /// Get tracks that are at the root level (not in any folder).
  List<Track> getRootTracks() {
    return _rootNodes['']?.tracks ?? [];
  }

  /// Get the contents of a virtual folder by path.
  /// Returns subfolders and tracks at that path.
  ({List<Folder> folders, List<Track> tracks}) getFolderContents(String folderPath) {
    final segments = folderPath.split('/');
    var currentLevel = _rootNodes;

    for (final segment in segments) {
      final node = currentLevel[segment];
      if (node == null) {
        return (folders: <Folder>[], tracks: <Track>[]);
      }
      if (segment == segments.last) {
        // Found the target folder
        final subfolders = node.children.entries
            .where((e) => e.key.isNotEmpty)
            .map((e) => e.value.toFolder())
            .toList()
          ..sort((a, b) => a.folderPath.toLowerCase().compareTo(b.folderPath.toLowerCase()));

        return (folders: subfolders, tracks: node.tracks);
      }
      currentLevel = node.children;
    }

    return (folders: <Folder>[], tracks: <Track>[]);
  }

  /// Get all tracks recursively under a folder path.
  List<Track> getAllTracksInFolder(String folderPath) {
    final segments = folderPath.split('/');
    var currentLevel = _rootNodes;

    for (final segment in segments) {
      final node = currentLevel[segment];
      if (node == null) return [];
      if (segment == segments.last) {
        return node.allTracksRecursive();
      }
      currentLevel = node.children;
    }

    return [];
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
