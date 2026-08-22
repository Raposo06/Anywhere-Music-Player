import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

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
      serverUrl: 'https://navidrome.example.com/',
      username: 'alice',
      password: 'secret',
    );

    test('buildStreamUrl strips a trailing slash and carries auth params', () {
      final url = api.buildStreamUrl('42');

      expect(url, startsWith('https://navidrome.example.com/rest/stream?id=42'));
      expect(url, contains('format=raw'));
      expect(url, isNot(contains('//rest/stream'))); // no doubled slash
      expect(url, matches(RegExp(r'u=alice')));
      expect(url, matches(RegExp(r'[?&]t=[0-9a-f]{32}'))); // md5 token
      expect(url, matches(RegExp(r'[?&]s=[a-z0-9]{12}'))); // salt
    });

    test('buildCoverArtUrl appends &size= only when requested', () {
      final base = api.buildCoverArtUrl('cov-1');
      final sized = api.buildCoverArtUrl('cov-1', size: 300);

      expect(base, startsWith('https://navidrome.example.com/rest/getCoverArt?id=cov-1'));
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
        serverUrl: 'https://navidrome.example.com',
        username: 'alice',
        password: 'secret',
        httpClient: client,
      );

      expect(await api.ping(), isTrue);
    });

    test('throws SubsonicApiException on bad credentials', () async {
      final client = MockClient((request) async => _subsonicError('Wrong username or password', code: 40));
      final api = SubsonicApiService(
        serverUrl: 'https://navidrome.example.com',
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
        serverUrl: 'https://navidrome.example.com',
        username: 'alice',
        password: 'secret',
        httpClient: client,
      );

      expect(() => api.ping(), throwsA(isA<SubsonicApiException>()));
    });

    test('throws SubsonicApiException when the response is not Subsonic-shaped', () async {
      final client = MockClient((request) async => http.Response('{"unexpected": true}', 200));
      final api = SubsonicApiService(
        serverUrl: 'https://navidrome.example.com',
        username: 'alice',
        password: 'secret',
        httpClient: client,
      );

      expect(() => api.ping(), throwsA(isA<SubsonicApiException>()));
    });
  });

  group('getMusicFolders', () {
    test('normalizes a single-object musicFolder into a one-item list', () async {
      final client = MockClient((request) async => _ok({
        'musicFolders': {
          'musicFolder': {'id': '1', 'name': 'Music'},
        },
      }));
      final api = SubsonicApiService(
        serverUrl: 'https://navidrome.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      final folders = await api.getMusicFolders();
      expect(folders, [{'id': '1', 'name': 'Music'}]);
    });

    test('returns an empty list when musicFolders is absent', () async {
      final client = MockClient((request) async => _ok({}));
      final api = SubsonicApiService(
        serverUrl: 'https://navidrome.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      expect(await api.getMusicFolders(), isEmpty);
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
        serverUrl: 'https://navidrome.example.com',
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
        serverUrl: 'https://navidrome.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      final result = await api.search3('nothing matches this');
      expect(result.songs, isEmpty);
      expect(result.albums, isEmpty);
    });
  });

  group('getMusicDirectory caching', () {
    test('serves the second call from cache without a second HTTP request', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return _ok({
          'directory': {'id': 'd1', 'child': []},
        });
      });
      final api = SubsonicApiService(
        serverUrl: 'https://navidrome.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      await api.getMusicDirectory('d1');
      await api.getMusicDirectory('d1');

      expect(requestCount, 1);
    });

    test('clearCache forces the next call to hit the network again', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return _ok({
          'directory': {'id': 'd1', 'child': []},
        });
      });
      final api = SubsonicApiService(
        serverUrl: 'https://navidrome.example.com',
        username: 'a',
        password: 'p',
        httpClient: client,
      );

      await api.getMusicDirectory('d1');
      api.clearCache();
      await api.getMusicDirectory('d1');

      expect(requestCount, 2);
    });
  });
}
