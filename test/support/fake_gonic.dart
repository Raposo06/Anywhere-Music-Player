import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// [path]'s last segment, extension stripped — a browse response's `title` is
/// tag metadata, not a filename, and Track.title takes it verbatim. A fixture
/// whose title still carried ".mp3" would make every title assertion wrong.
String _titleFromPath(String path) {
  final base = path.split('/').last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

/// One song, shaped the way a Subsonic browse response carries it.
///
/// [path] is what [gonicBrowseClient] derives the served directory tree from,
/// so a test writes the library it wants as a list of paths.
Map<String, dynamic> browseSong({
  required String id,
  required String path,
  String? coverArtId,
  String? artist,
  String? album,
}) => {
  'id': id,
  'path': path,
  'title': _titleFromPath(path),
  'isDir': false,
  'coverArt': coverArtId,
  'duration': 120,
  'size': 1000,
  'artist': artist,
  'album': album,
};

/// A [http.Client] standing in for a folder-native Subsonic server (Gonic).
///
/// Derives a real directory tree from [songs]' paths and serves the three
/// browse endpoints `SubsonicApiService.getAllTracksByFolder` walks —
/// `getMusicFolders`, `getIndexes`, `getMusicDirectory`. A directory's id is
/// its own path here; real servers use opaque ids, and nothing under test may
/// depend on the difference.
///
/// One music folder, so the walk leaves its name out of the synthesized paths
/// and they come back exactly as they went in. Multi-folder prefixing has its
/// own test in test/services/subsonic_api_service_test.dart.
http.Client gonicBrowseClient(List<Map<String, dynamic>> songs) {
  // Rebuilt per request, not once up front: a test that exercises a rescan
  // adds to its fixture list between the two scans and expects the second one
  // to see the addition, the way a real server would after a rescan.
  ({
    Map<String, Set<String>> subdirs,
    Map<String, List<Map<String, dynamic>>> direct,
  })
  index() {
    // Directory path -> its immediate subdirectory names / its own songs.
    // '' is the music-folder root, which getIndexes serves rather than
    // getMusicDirectory.
    final subdirs = <String, Set<String>>{'': <String>{}};
    final direct = <String, List<Map<String, dynamic>>>{'': []};

    void ensure(String dir) {
      subdirs.putIfAbsent(dir, () => <String>{});
      direct.putIfAbsent(dir, () => []);
    }

    for (final song in songs) {
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

    return (subdirs: subdirs, direct: direct);
  }

  return MockClient((request) async {
    final tree = index();
    final subdirs = tree.subdirs;
    final direct = tree.direct;

    List<Map<String, dynamic>> childrenOf(String dir) => [
      for (final name in subdirs[dir]!.toList()..sort())
        {'id': dir.isEmpty ? name : '$dir/$name', 'title': name, 'isDir': true},
      ...direct[dir]!,
    ];

    switch (request.url.pathSegments.last) {
      case 'getMusicFolders':
        return _ok({
          'musicFolders': {
            'musicFolder': [
              {'id': '0', 'name': 'music'},
            ],
          },
        });

      case 'getIndexes':
        return _ok({
          'indexes': {
            // Subsonic buckets top-level directories alphabetically; the walk
            // flattens the buckets away, so one bucket holding all of them is
            // as faithful as spelling out A–Z.
            'index': [
              {
                'name': '#',
                'artist': [
                  for (final name in subdirs['']!.toList()..sort())
                    {'id': name, 'name': name},
                ],
              },
            ],
            'child': direct['']!,
          },
        });

      case 'getMusicDirectory':
        final id = request.url.queryParameters['id'];
        if (id == null || !subdirs.containsKey(id)) {
          return http.Response('not found', 404);
        }
        return _ok({
          'directory': {'id': id, 'child': childrenOf(id)},
        });

      default:
        return http.Response('not found', 404);
    }
  });
}

http.Response _ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {
      'status': 'ok',
      'version': '1.15.0',
      'type': 'gonic',
      ...body,
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);
