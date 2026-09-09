import 'package:anywhere_music_player/services/library_browser.dart';

export 'fake_gonic.dart' show browseSong;

/// An in-memory [LibraryBrowser] built straight from song maps.
///
/// The second adapter at the [LibraryBrowser] seam, and the reason the seam is
/// real rather than hypothetical: a walk test that only wants to know where a
/// track lands should not have to stand up an HTTP server to ask.
/// [gonicBrowseClient] still covers the transport's own parsing.
///
/// A directory's id is its own path. Real servers use opaque ids and nothing
/// under test may depend on the difference.
class FakeBrowser implements LibraryBrowser {
  FakeBrowser(this._songs, {List<BrowseDir>? musicFolders})
    : _musicFolders = musicFolders ?? const [(id: '0', name: 'music')];

  final List<Map<String, dynamic>> _songs;
  final List<BrowseDir> _musicFolders;

  /// Directory path -> immediate subdirectory names, and -> its own songs.
  /// `''` is the music-folder root, which [getIndexes] serves.
  (Map<String, Set<String>>, Map<String, List<Map<String, dynamic>>>) _index() {
    final subdirs = <String, Set<String>>{'': <String>{}};
    final direct = <String, List<Map<String, dynamic>>>{'': []};

    void ensure(String dir) {
      subdirs.putIfAbsent(dir, () => <String>{});
      direct.putIfAbsent(dir, () => []);
    }

    for (final song in _songs) {
      final segments = (song['path'] as String).split('/');
      var parent = '';
      for (var i = 0; i < segments.length - 1; i++) {
        final dir = parent.isEmpty ? segments[i] : '$parent/${segments[i]}';
        ensure(parent);
        ensure(dir);
        subdirs[parent]!.add(segments[i]);
        parent = dir;
      }
      ensure(parent);
      direct[parent]!.add(song);
    }
    return (subdirs, direct);
  }

  @override
  Future<List<BrowseDir>> getMusicFolders() async => _musicFolders;

  @override
  Future<BrowseListing> getIndexes({String? musicFolderId}) async {
    final (subdirs, direct) = _index();
    return (
      directories: [
        for (final name in subdirs['']!.toList()..sort()) (id: name, name: name),
      ],
      songs: direct['']!,
    );
  }

  @override
  Future<BrowseListing> getMusicDirectory(String id) async {
    final (subdirs, direct) = _index();
    if (!subdirs.containsKey(id)) {
      return (directories: <BrowseDir>[], songs: <Map<String, dynamic>>[]);
    }
    return (
      directories: [
        for (final name in subdirs[id]!.toList()..sort())
          (id: '$id/$name', name: name),
      ],
      songs: direct[id]!,
    );
  }
}
