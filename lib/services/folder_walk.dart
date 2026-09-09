import '../models/track.dart';
import 'library_browser.dart';

/// Walks the server's own directory tree and returns every song under it.
/// This is the library scan.
///
/// Lives here rather than on the transport because none of it is transport:
/// it is a traversal (breadth-first, [_concurrency] directories per round
/// trip, with a visited set so a server that reports a directory as its own
/// descendant cannot make it loop) plus a path policy ([_pathOf]). What it
/// needs from a server is three calls — see [LibraryBrowser].
///
/// [LibraryScanner] is the only caller: it takes the flat list this returns,
/// caches it, and rebuilds the browsable tree from the paths on it.
class FolderWalk {
  FolderWalk(this._browser);

  final LibraryBrowser _browser;

  /// Directories fetched in parallel by [run]. Enough to keep a scan from
  /// being latency-bound, low enough not to look like a burst to a small
  /// self-hosted server.
  static const int _concurrency = 8;

  /// Walk the server's real directory tree and return every song under it.
  /// This is the library scan.
  ///
  /// Each [Track] carries a library-relative path (`Anime/Naruto/01 -
  /// Opening.flac`), which is what [LibraryScanner] rebuilds the browsable
  /// tree from. It is read from the song's own `path` field, and only
  /// synthesized from the descent when the server omits it or sends an
  /// absolute one.
  ///
  /// This used to be the other way round. The walk is only as folder-shaped
  /// as `getIndexes` is: Gonic answered it with a tag-shaped artist index
  /// (`5050/One Piece/…`, `[Unknown Artist]/[Unknown Album]/…`), and the
  /// synthesized path faithfully reproduced that instead of the on-disk tree
  /// the folder browser exists to show. The song's `path` is the on-disk
  /// tree. See docs/decisions.md.
  ///
  /// Walked breadth-first, [_concurrency] directories per round trip. A
  /// folder-native server answers one directory per request, so a library of
  /// a few thousand directories is a few thousand requests — issuing them
  /// strictly one after another is what would make a scan feel slow.
  Future<List<Track>> run({
    void Function(int songsSoFar)? onProgress,
  }) async {
    final musicFolders = await _browser.getMusicFolders();

    // With one music folder its name is left out of the path, so paths stay
    // relative to the music root — the shape the folder tree, the on-disk
    // cache and the now-playing folder line were all built around. With
    // several, the name becomes the top-level segment that tells them apart.
    final prefixWithFolderName = musicFolders.length > 1;

    final tracks = <Track>[];
    // Every directory id this walk has already queued. A server that reports a
    // directory as its own descendant — or the same shared directory under two
    // music folders — would otherwise loop forever, or at best duplicate every
    // track under it. Nothing observed does this; the walk is recursive over
    // data from the network, which is reason enough not to trust it to
    // terminate on its own.
    final visited = <String>{};
    var level = <({String id, String path, String root})>[];

    for (final folder in musicFolders) {
      final root = prefixWithFolderName ? folder.name : '';
      final top = await _browser.getIndexes(musicFolderId: folder.id);
      tracks.addAll(_tracksIn(top.songs, root, root));
      for (final dir in top.directories) {
        if (!visited.add(dir.id)) continue;
        level.add((id: dir.id, path: _joinPath(root, dir.name), root: root));
      }
    }

    while (level.isNotEmpty) {
      final next = <({String id, String path, String root})>[];
      for (var i = 0; i < level.length; i += _concurrency) {
        final batch = level.skip(i).take(_concurrency);
        final listings = await Future.wait([
          for (final entry in batch)
            _browser.getMusicDirectory(
              entry.id,
            ).then((contents) => (entry: entry, contents: contents)),
        ]);
        for (final listing in listings) {
          tracks.addAll(_tracksIn(
            listing.contents.songs,
            listing.entry.path,
            listing.entry.root,
          ));
          for (final dir in listing.contents.directories) {
            if (!visited.add(dir.id)) continue;
            next.add((
              id: dir.id,
              path: _joinPath(listing.entry.path, dir.name),
              root: listing.entry.root,
            ));
          }
        }
        onProgress?.call(tracks.length);
      }
      level = next;
    }

    // Path order — what the previous whole-library fetch sorted by, and what
    // every list in the UI still expects. The walk finishes breadth-first, so
    // without this the flat list interleaves depths.
    tracks.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return tracks;
  }

  static List<Track> _tracksIn(
    List<Map<String, dynamic>> songs,
    String dirPath,
    String root,
  ) => [
    for (final song in songs)
      Track.fromSubsonic(song, resolvedPath: _pathOf(song, dirPath, root)),
  ];

  /// The library-relative path a track is filed under.
  ///
  /// Prefers the server's own `path`, because on a folder-native server that
  /// *is* the on-disk tree — the thing the folder browser exists to show — and
  /// it stays correct however `getIndexes` chooses to shape its index. [root]
  /// is the music folder's name, non-empty only when there's more than one
  /// folder to tell apart; the server's path is relative to its own music
  /// folder, so it needs that prefix to stay unambiguous.
  ///
  /// Falls back to the walked path in the two cases where the server's is
  /// unusable:
  ///
  /// - **absent or empty** — the Subsonic spec doesn't require `path`;
  /// - **absolute** (`/mnt/music/…`, `C:\Music\…`) — a filesystem path whose
  ///   library root this client can't know, so there is nothing safe to strip.
  ///   Navidrome sent these, which is why the walk existed in the first place.
  static String _pathOf(
    Map<String, dynamic> song,
    String dirPath,
    String root,
  ) {
    final serverPath = (song['path'] as String?)?.replaceAll('\\', '/').trim();
    if (serverPath != null && serverPath.isNotEmpty && !_isAbsolute(serverPath)) {
      final cleaned = serverPath
          .split('/')
          .where((seg) => seg.isNotEmpty && seg != '.')
          .join('/');
      if (cleaned.isNotEmpty) return _joinPath(root, cleaned);
    }
    return _joinPath(dirPath, _fileNameOf(song));
  }

  /// True for a path rooted at a filesystem, POSIX (`/music/x`) or Windows
  /// (`C:/music/x`, `//server/share/x`) — separators already normalised to `/`.
  static bool _isAbsolute(String path) {
    if (path.startsWith('/')) return true;
    return path.length >= 2 &&
        path[1] == ':' &&
        RegExp(r'^[A-Za-z]$').hasMatch(path[0]);
  }

  static String _joinPath(String parent, String child) =>
      parent.isEmpty ? child : '$parent/$child';

  /// The song's own file name, for the last segment of its synthesized path.
  /// Prefers the basename of whatever `path` the server sends, falling back to
  /// title + suffix — which a browse response always carries.
  static String _fileNameOf(Map<String, dynamic> song) {
    final serverPath = song['path'] as String?;
    if (serverPath != null && serverPath.isNotEmpty) {
      return serverPath.split('/').last;
    }
    final title = song['title'] as String? ?? song['id'].toString();
    final suffix = song['suffix'] as String?;
    return (suffix != null && suffix.isNotEmpty) ? '$title.$suffix' : title;
  }
}
