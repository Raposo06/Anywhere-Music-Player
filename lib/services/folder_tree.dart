import '../models/folder.dart';
import '../models/track.dart';

/// The browsable folder tree, derived from a flat list of [Track]s.
///
/// Immutable and pure — no Flutter, no HTTP, no filesystem — so the rules that
/// decide what the user sees when they browse can be tested by handing this a
/// list of paths. Rebuilt whole on every scan; there is no incremental update.
///
/// A library whose entire content sits under one top-level folder is *flattened*:
/// that folder is skipped and its children are shown as the top level, because
/// a home screen with exactly one row in it is not a useful home screen. The
/// rule is resolved once here, at construction, rather than recomputed at each
/// query — it used to be spelled out three separate times, three slightly
/// different ways.
class FolderTree {
  FolderTree._(this._roots, this._flattened, this._byId);

  /// The tree with nothing in it — logged out, or before the first scan.
  static final FolderTree empty = FolderTree._(
    const <String, _Node>{},
    null,
    const <String, Track>{},
  );

  /// Build the tree from [tracks], filing each under its own [Track.path].
  factory FolderTree.from(List<Track> tracks) {
    final roots = <String, _Node>{};

    for (final track in tracks) {
      // e.g. "Anime/Naruto/23.Senya.mp3"
      final segments = track.path.split('/');

      if (segments.length < 2) {
        // Loose at the library root: filed under the unnamed root node.
        roots.putIfAbsent('', () => _Node(name: '', fullPath: ''));
        roots['']!.tracks.add(track);
        continue;
      }

      var level = roots;
      var path = '';

      for (var i = 0; i < segments.length - 1; i++) {
        final segment = segments[i];
        path = path.isEmpty ? segment : '$path/$segment';

        final node = level.putIfAbsent(
          segment,
          () => _Node(name: segment, fullPath: path),
        );

        if (i == segments.length - 2) {
          node.tracks.add(track);
          // First track with a cover gives the folder its cover.
          node.coverArtId ??= track.coverArtId;
        }

        level = node.children;
      }
    }

    return FolderTree._(
      roots,
      _flattenedRootOf(roots),
      {for (final track in tracks) track.id: track},
    );
  }

  final Map<String, _Node> _roots;

  /// The single top-level node that was flattened away, or null when the
  /// library has no such node. The one place the flatten rule is decided.
  final _Node? _flattened;

  final Map<String, Track> _byId;

  static _Node? _flattenedRootOf(Map<String, _Node> roots) {
    final named = roots.entries.where((e) => e.key.isNotEmpty).toList();
    if (named.length != 1) return null;
    final only = named.first.value;
    return only.children.isEmpty ? null : only;
  }

  Map<String, _Node> get _effectiveRoot => _flattened?.children ?? _roots;

  /// The scanned copy of [id] — the one carrying a real library path — or null.
  /// Lets a track that arrived by another route (a playlist fetch, whose paths
  /// are tag-based) be resolved back to its canonical form.
  Track? trackById(String id) => _byId[id];

  /// True iff [folderPath] is the top-level folder that was flattened away.
  /// A UI surface that would otherwise push a folder screen duplicating the
  /// home screen should treat a tap on it as "go home" instead.
  bool isFlattenedRoot(String folderPath) {
    final flattened = _flattened;
    return flattened != null && flattened.fullPath == folderPath;
  }

  /// The folders shown at the top level, flattening applied.
  List<Folder> topLevelFolders() => _foldersIn(_effectiveRoot);

  /// Tracks sitting outside any folder. When the root was flattened, these are
  /// the skipped folder's own direct tracks.
  List<Track> rootTracks() =>
      _flattened?.tracks ?? _roots['']?.tracks ?? const <Track>[];

  /// The subfolders and tracks directly inside [folderPath].
  ({List<Folder> folders, List<Track> tracks}) contentsOf(String folderPath) {
    final node = _find(folderPath);
    if (node == null) {
      return (folders: <Folder>[], tracks: <Track>[]);
    }
    return (folders: _foldersIn(node.children), tracks: node.tracks);
  }

  /// Every track under [folderPath], recursively.
  List<Track> allTracksUnder(String folderPath) =>
      _find(folderPath)?.allTracksRecursive() ?? const <Track>[];

  /// Folders whose *leaf* name contains [query], case-insensitively. Matching
  /// the full path would surface every child of a matching parent, which
  /// clutters results. Sorted by depth (top-level first), then alphabetically.
  List<Folder> searchFolders(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <Folder>[];

    final matches = <_Node>[];
    void walk(_Node node) {
      if (node.fullPath.isNotEmpty && node.name.toLowerCase().contains(needle)) {
        matches.add(node);
      }
      for (final child in node.children.values) {
        walk(child);
      }
    }

    for (final root in _roots.values) {
      walk(root);
    }

    matches.sort((a, b) {
      final depthA = '/'.allMatches(a.fullPath).length;
      final depthB = '/'.allMatches(b.fullPath).length;
      if (depthA != depthB) return depthA - depthB;
      return a.fullPath.toLowerCase().compareTo(b.fullPath.toLowerCase());
    });

    return [for (final node in matches) node.toFolder()];
  }

  /// Named children of [level] as UI folders, path-sorted. The unnamed root
  /// node holds loose tracks, not a folder, so it is never listed.
  static List<Folder> _foldersIn(Map<String, _Node> level) =>
      [
        for (final entry in level.entries)
          if (entry.key.isNotEmpty) entry.value.toFolder(),
      ]..sort(
        (a, b) =>
            a.folderPath.toLowerCase().compareTo(b.folderPath.toLowerCase()),
      );

  _Node? _find(String folderPath) {
    final segments = folderPath.split('/');
    var level = _roots;
    for (var i = 0; i < segments.length; i++) {
      final node = level[segments[i]];
      if (node == null) return null;
      if (i == segments.length - 1) return node;
      level = node.children;
    }
    return null;
  }
}

/// Internal tree node representing a folder in the virtual hierarchy.
class _Node {
  final String name;
  final String fullPath;
  final Map<String, _Node> children = {};
  final List<Track> tracks = [];
  String? coverArtId;

  _Node({required this.name, required this.fullPath});

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

  /// Convert to a Folder model for the UI. Carries only the cover art id —
  /// the URL is resolved at the point of use (see StreamUrlResolver).
  Folder toFolder() {
    return Folder(
      id: fullPath, // Use the path as ID for virtual folders
      folderPath: fullPath,
      trackCount: totalTrackCount,
      coverArtId: coverArtId ?? _findFirstCoverArtId(),
      albumCount: subfolderCount,
    );
  }

  /// Find the first cover art id from any track in this folder or subfolders.
  String? _findFirstCoverArtId() {
    for (final track in tracks) {
      if (track.coverArtId != null) return track.coverArtId;
    }
    for (final child in children.values) {
      final id = child._findFirstCoverArtId();
      if (id != null) return id;
    }
    return null;
  }
}
