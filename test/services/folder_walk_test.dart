import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/services/folder_walk.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import '../support/fake_browser.dart';
import '../support/fake_gonic.dart';

http.Response _ok(Map<String, dynamic> subsonicResponse) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...subsonicResponse},
  }),
  200,
);

void main() {
  group('FolderWalk.run (the library scan)', () {
    SubsonicApiService apiOver(List<Map<String, dynamic>> songs) =>
        SubsonicApiService(
          serverUrl: 'https://gonic.example.com',
          username: 'alice',
          password: 'secret',
          httpClient: gonicBrowseClient(songs),
        );

    test('synthesizes each path from the directories it descended', () async {
      final api = apiOver([
        browseSong(id: '1', path: 'Anime/Naruto/01 - Opening.mp3'),
        browseSong(id: '2', path: 'Rock/Album/02 - Song.mp3'),
      ]);

      final tracks = await FolderWalk(api).run();

      expect(tracks.map((t) => t.path), [
        'Anime/Naruto/01 - Opening.mp3',
        'Rock/Album/02 - Song.mp3',
      ]);
      expect(tracks.first.folderPath, 'Anime/Naruto');
      expect(tracks.first.folderName, 'Naruto');
    });

    test('picks up loose songs at the music-folder root, from getIndexes', () async {
      final api = apiOver([
        browseSong(id: '1', path: 'loose.mp3'),
        browseSong(id: '2', path: 'Anime/song.mp3'),
      ]);

      final tracks = await FolderWalk(api).run();
      final loose = tracks.firstWhere((t) => t.id == '1');

      expect(loose.path, 'loose.mp3');
      expect(loose.folderPath, isEmpty);
      expect(loose.folderName, isEmpty);
    });

    test('returns tracks in path order, not the order the walk finished in', () async {
      // Breadth-first, so 'Zebra/song.mp3' (depth 1) is fetched before
      // 'Anime/Naruto/song.mp3' (depth 2) — the sort is what puts them back.
      final api = apiOver([
        browseSong(id: '1', path: 'Zebra/song.mp3'),
        browseSong(id: '2', path: 'Anime/Naruto/song.mp3'),
      ]);

      final tracks = await FolderWalk(api).run();

      expect(tracks.map((t) => t.path), [
        'Anime/Naruto/song.mp3',
        'Zebra/song.mp3',
      ]);
    });

    test('walks a level wider than the concurrency window without dropping any', () async {
      // 20 top-level directories against a window of 8: the batching loop has
      // to come back for the remainder rather than stopping at the first round.
      final api = apiOver([
        for (var i = 0; i < 20; i++)
          browseSong(id: '$i', path: 'Folder${i.toString().padLeft(2, '0')}/song.mp3'),
      ]);

      final tracks = await FolderWalk(api).run();

      expect(tracks, hasLength(20));
      expect(tracks.map((t) => t.id).toSet(), hasLength(20));
    });

    test('walks deeper than one level below the top', () async {
      final api = apiOver([
        browseSong(id: '1', path: 'A/B/C/D/deep.mp3'),
      ]);

      final tracks = await FolderWalk(api).run();

      expect(tracks.single.path, 'A/B/C/D/deep.mp3');
      expect(tracks.single.folderPath, 'A/B/C/D');
    });

    test('names the music folder in the path only when there is more than one', () async {
      // Two music folders can hold identically-named top-level directories, so
      // the folder name becomes the segment that tells them apart. With one,
      // adding it would push a redundant level into every path. The server's
      // `path` is relative to its own music folder, so the name goes on in
      // front of it.
      final client = MockClient((request) async {
        switch (request.url.pathSegments.last) {
          case 'getMusicFolders':
            return _ok({
              'musicFolders': {
                'musicFolder': [
                  {'id': '0', 'name': 'FLAC'},
                  {'id': '1', 'name': 'MP3'},
                ],
              },
            });
          case 'getIndexes':
            final folder = request.url.queryParameters['musicFolderId'];
            return _ok({
              'indexes': {
                'index': [
                  {
                    'name': 'R',
                    'artist': [
                      {'id': 'rock-$folder', 'name': 'Rock'},
                    ],
                  },
                ],
              },
            });
          case 'getMusicDirectory':
            final id = request.url.queryParameters['id'];
            return _ok({
              'directory': {
                'id': id,
                'child': [
                  {
                    'id': 'song-$id',
                    'title': 'Song',
                    'isDir': false,
                    'path': 'Rock/Song.flac',
                  },
                ],
              },
            });
        }
        return http.Response('not found', 404);
      });

      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      final tracks = await FolderWalk(api).run();

      expect(tracks.map((t) => t.path), [
        'FLAC/Rock/Song.flac',
        'MP3/Rock/Song.flac',
      ]);
    });

    test("the song's own path decides the tree, not the directories walked", () async {
      // The bug this exists to catch: Gonic answered getIndexes with a
      // tag-shaped artist index, so the walk descended '5050/One Piece' and
      // synthesized that as the path — burying the on-disk folder tree the
      // browser exists to show. The song's `path` carries the real one.
      final client = MockClient((request) async {
        switch (request.url.pathSegments.last) {
          case 'getMusicFolders':
            return _ok({
              'musicFolders': {
                'musicFolder': {'id': '0', 'name': 'music'},
              },
            });
          case 'getIndexes':
            return _ok({
              'indexes': {
                'index': {
                  'name': '5',
                  'artist': {'id': 'artist-5050', 'name': '5050'},
                },
              },
            });
          case 'getMusicDirectory':
            final id = request.url.queryParameters['id'];
            if (id == 'artist-5050') {
              return _ok({
                'directory': {
                  'id': id,
                  'child': {'id': 'album-op', 'name': 'One Piece', 'isDir': true},
                },
              });
            }
            return _ok({
              'directory': {
                'id': id,
                'child': {
                  'id': 'song-1',
                  'title': 'Jungle P',
                  'isDir': false,
                  'path': 'ANIMES & ANIMATIONS/One Piece/01-Jungle P.mp3',
                },
              },
            });
        }
        return http.Response('not found', 404);
      });

      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      final tracks = await FolderWalk(api).run();

      expect(tracks.single.path, 'ANIMES & ANIMATIONS/One Piece/01-Jungle P.mp3');
      expect(tracks.single.folderPath, 'ANIMES & ANIMATIONS/One Piece');
      expect(tracks.single.folderName, 'One Piece');
    });

    test('falls back to the walked path when the server sends an absolute one', () async {
      // Navidrome sent filesystem paths. There is no way to know which prefix
      // is the library root, so nothing can safely be stripped — the walk is
      // the only trustworthy source in that case.
      final client = MockClient((request) async {
        switch (request.url.pathSegments.last) {
          case 'getMusicFolders':
            return _ok({
              'musicFolders': {
                'musicFolder': {'id': '0', 'name': 'music'},
              },
            });
          case 'getIndexes':
            return _ok({
              'indexes': {
                'index': {
                  'name': 'A',
                  'artist': {'id': 'dir-anime', 'name': 'Anime'},
                },
              },
            });
          case 'getMusicDirectory':
            return _ok({
              'directory': {
                'id': request.url.queryParameters['id'],
                'child': {
                  'id': 'song-1',
                  'title': 'Song',
                  'isDir': false,
                  'path': '/mnt/storagebox/music/Whatever/song.mp3',
                },
              },
            });
        }
        return http.Response('not found', 404);
      });

      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      final tracks = await FolderWalk(api).run();

      expect(tracks.single.path, 'Anime/song.mp3');
    });

    test('falls back to title + suffix when the server sends no path', () async {
      final client = MockClient((request) async {
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
                'index': [
                  {
                    'name': 'A',
                    'artist': [
                      {'id': 'dir-1', 'name': 'Anime'},
                    ],
                  },
                ],
              },
            });
          case 'getMusicDirectory':
            return _ok({
              'directory': {
                'id': 'dir-1',
                // No `path` — Subsonic does not require one on a child.
                'child': [
                  {
                    'id': '1',
                    'title': 'Opening',
                    'suffix': 'flac',
                    'isDir': false,
                  },
                ],
              },
            });
        }
        return http.Response('not found', 404);
      });

      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      final tracks = await FolderWalk(api).run();

      expect(tracks.single.path, 'Anime/Opening.flac');
      expect(tracks.single.folderPath, 'Anime');
    });
  });

  group('FolderWalk.run (no transport)', () {
    test('returns tracks in path order, not walk-completion order', () async {
      final walk = FolderWalk(FakeBrowser([
        browseSong(id: '1', path: 'Zebra/song.mp3'),
        browseSong(id: '2', path: 'Anime/Naruto/song.mp3'),
      ]));

      final tracks = await walk.run();

      expect(tracks.map((t) => t.path), [
        'Anime/Naruto/song.mp3',
        'Zebra/song.mp3',
      ]);
    });

    test('a level wider than the concurrency window loses nothing', () async {
      final walk = FolderWalk(FakeBrowser([
        for (var i = 0; i < 20; i++)
          browseSong(id: '$i', path: 'Dir$i/song.mp3'),
      ]));

      expect((await walk.run()).length, 20);
    });

    test('names the music folder in the path only when there is more than one',
        () async {
      final walk = FolderWalk(FakeBrowser(
        [browseSong(id: '1', path: 'Anime/song.mp3')],
        musicFolders: const [(id: '0', name: 'music')],
      ));

      expect((await walk.run()).single.path, 'Anime/song.mp3');
    });
  });
}
