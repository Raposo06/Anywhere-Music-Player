import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import '../support/fake_gonic.dart';

http.Response _ok(Map<String, dynamic> subsonicResponse) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...subsonicResponse},
  }),
  200,
);

http.Response _subsonicError(String message, {int code = 40}) => http.Response(
  jsonEncode({
    'subsonic-response': {
      'status': 'failed',
      'error': {'code': code, 'message': message},
    },
  }),
  200,
);

void main() {
  group('URL building (pure, no network)', () {
    final api = SubsonicApiService(
      serverUrl: 'https://gonic.example.com/',
      username: 'alice',
      password: 'secret',
    );

    test('buildStreamUrl strips a trailing slash and carries auth params', () {
      final url = api.buildStreamUrl('42');

      expect(url, startsWith('https://gonic.example.com/rest/stream?id=42'));
      expect(url, contains('format=raw'));
      expect(url, isNot(contains('//rest/stream'))); // no doubled slash
      expect(url, matches(RegExp(r'u=alice')));
      expect(url, matches(RegExp(r'[?&]t=[0-9a-f]{32}'))); // md5 token
      expect(url, matches(RegExp(r'[?&]s=[a-z0-9]{12}'))); // salt
    });

    test('buildCoverArtUrl appends &size= only when requested', () {
      final base = api.buildCoverArtUrl('cov-1');
      final sized = api.buildCoverArtUrl('cov-1', size: 300);

      expect(base, startsWith('https://gonic.example.com/rest/getCoverArt?id=cov-1'));
      expect(base, isNot(contains('size=')));
      expect(sized, contains('&size=300'));
    });

    test('the auth salt/token rotate on every call — never cacheable by URL', () {
      final first = api.buildStreamUrl('42');
      final second = api.buildStreamUrl('42');

      expect(first, isNot(second));
    });

    test('never sends the password itself, only an md5(password+salt) token', () {
      final url = api.buildStreamUrl('42');
      expect(url, isNot(contains('secret')));
    });
  });

  group('ping', () {
    test('returns true on a successful response', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/rest/ping');
        return _ok({});
      });
      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'alice',
        password: 'secret',
        httpClient: client,
      );

      expect(await api.ping(), isTrue);
    });

    test('throws SubsonicApiException on bad credentials', () async {
      final client = MockClient((request) async => _subsonicError('Wrong username or password', code: 40));
      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'alice',
        password: 'wrong',
        httpClient: client,
      );

      expect(
        () => api.ping(),
        throwsA(isA<SubsonicApiException>().having((e) => e.code, 'code', 40)),
      );
    });

    test('throws SubsonicApiException on an HTTP error status', () async {
      final client = MockClient((request) async => http.Response('Server Error', 500));
      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'alice',
        password: 'secret',
        httpClient: client,
      );

      expect(() => api.ping(), throwsA(isA<SubsonicApiException>()));
    });

    test('throws SubsonicApiException when the response is not Subsonic-shaped', () async {
      final client = MockClient((request) async => http.Response('{"unexpected": true}', 200));
      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'alice',
        password: 'secret',
        httpClient: client,
      );

      expect(() => api.ping(), throwsA(isA<SubsonicApiException>()));
    });
  });

  group('search3', () {
    test('parses songs and albums, normalizing single-object results into lists', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/rest/search3');
        expect(request.url.queryParameters['query'], 'test query');
        return _ok({
          'searchResult3': {
            'song': {'id': '1', 'title': 'Solo Song'},
            'album': [
              {'id': 'a1', 'name': 'Album One'},
              {'id': 'a2', 'name': 'Album Two'},
            ],
          },
        });
      });
      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      final result = await api.search3('test query');

      expect(result.songs, hasLength(1));
      expect(result.songs.single.title, 'Solo Song');
      expect(result.albums, hasLength(2));
      expect(result.albums.map((f) => f.folderPath), ['Album One', 'Album Two']);
    });

    test('returns empty results when searchResult3 is absent (no matches)', () async {
      final client = MockClient((request) async => _ok({}));
      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      final result = await api.search3('nothing matches this');
      expect(result.songs, isEmpty);
      expect(result.albums, isEmpty);
    });

    test('a Subsonic-level error rethrows unchanged, not double-wrapped', () async {
      final client = MockClient((request) async => _subsonicError('Bad query', code: 10));
      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      expect(
        () => api.search3('x'),
        throwsA(isA<SubsonicApiException>().having((e) => e.message, 'message', 'Bad query')),
      );
    });
  });

  group('scrobble', () {
    /// Captures the single request an API call makes, so a test can assert on
    /// the query it built.
    ({SubsonicApiService api, List<Uri> requests}) buildApi() {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return _ok({});
      });
      return (
        api: SubsonicApiService(
          serverUrl: 'https://gonic.example.com',
          username: 'a',
          password: 'p',
          httpClient: client,
        ),
        requests: requests,
      );
    }

    test('nowPlaying posts submission=false', () async {
      final (:api, :requests) = buildApi();

      await api.nowPlaying('song-1');

      final uri = requests.single;
      expect(uri.path, '/rest/scrobble');
      expect(uri.queryParameters['id'], 'song-1');
      expect(uri.queryParameters['submission'], 'false');
      // An announcement carries no play time — it isn't a play.
      expect(uri.queryParameters, isNot(contains('time')));
    });

    test('scrobble posts submission=true with the listen start time', () async {
      final (:api, :requests) = buildApi();
      final startedAt = DateTime.utc(2026, 8, 30, 12, 34, 56);

      await api.scrobble('song-1', startedAt: startedAt);

      final uri = requests.single;
      expect(uri.path, '/rest/scrobble');
      expect(uri.queryParameters['id'], 'song-1');
      expect(uri.queryParameters['submission'], 'true');
      expect(uri.queryParameters['time'],
          startedAt.millisecondsSinceEpoch.toString());
    });

    test('scrobble omits time when no start is given', () async {
      final (:api, :requests) = buildApi();

      await api.scrobble('song-1');

      expect(requests.single.queryParameters, isNot(contains('time')));
    });

    test('a server that rejects the scrobble throws, for the caller to swallow',
        () async {
      final client = MockClient(
        (request) async => _subsonicError('Not implemented', code: 30),
      );
      final api = SubsonicApiService(
        serverUrl: 'https://gonic.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      // AudioPlayerService is what swallows this — see its _report().
      expect(() => api.scrobble('song-1'), throwsA(isA<SubsonicApiException>()));
    });
  });

  group('getAllTracksByFolder (the library scan)', () {
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

      final tracks = await api.getAllTracksByFolder();

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

      final tracks = await api.getAllTracksByFolder();
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

      final tracks = await api.getAllTracksByFolder();

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

      final tracks = await api.getAllTracksByFolder();

      expect(tracks, hasLength(20));
      expect(tracks.map((t) => t.id).toSet(), hasLength(20));
    });

    test('walks deeper than one level below the top', () async {
      final api = apiOver([
        browseSong(id: '1', path: 'A/B/C/D/deep.mp3'),
      ]);

      final tracks = await api.getAllTracksByFolder();

      expect(tracks.single.path, 'A/B/C/D/deep.mp3');
      expect(tracks.single.folderPath, 'A/B/C/D');
    });

    test('names the music folder in the path only when there is more than one', () async {
      // Two music folders can hold identically-named top-level directories, so
      // the folder name becomes the segment that tells them apart. With one,
      // adding it would push a redundant level into every path.
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
                    'path': 'whatever/Song.flac',
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

      final tracks = await api.getAllTracksByFolder();

      expect(tracks.map((t) => t.path), [
        'FLAC/Rock/Song.flac',
        'MP3/Rock/Song.flac',
      ]);
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

      final tracks = await api.getAllTracksByFolder();

      expect(tracks.single.path, 'Anime/Opening.flac');
      expect(tracks.single.folderPath, 'Anime');
    });
  });
}
