/// One entry in a browse response's directory listing.
typedef BrowseDir = ({String id, String name});

/// One directory's immediate children, split into subdirectories and songs.
///
/// [songs] are raw Subsonic song objects, deliberately. The walk has to read
/// each song's own `path` to decide where the track is filed, and then hand
/// the same map to `Track.fromSubsonic` — parsing them into models here would
/// put the path policy back inside the transport, which is the thing this
/// seam exists to prevent.
typedef BrowseListing = ({
  List<BrowseDir> directories,
  List<Map<String, dynamic>> songs,
});

/// Reading the server's directory tree, one directory at a time.
///
/// The three calls a folder-native Subsonic server answers, and the whole of
/// what [FolderWalk] needs from a server. Implemented by [SubsonicApiService]
/// in production and by a in-memory tree in tests.
abstract class LibraryBrowser {
  /// The server's configured music folders.
  Future<List<BrowseDir>> getMusicFolders();

  /// The top level of a music folder: its immediate child directories, plus
  /// any songs sitting loose at the music-folder root.
  Future<BrowseListing> getIndexes({String? musicFolderId});

  /// One directory's immediate children.
  Future<BrowseListing> getMusicDirectory(String id);
}
