import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/models/playlist.dart';
import 'package:anywhere_music_player/services/playlists_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import '../support/fixtures.dart';

// Covers PlaylistsService and the playlist endpoints beneath it.
//
// The deliberate contrast with FavouritesService is that nothing here is
// optimistic: every mutation waits for the server and re-reads, because
// Subsonic removes playlist tracks by position and acting on a stale copy can
// delete the wrong one. See docs/decisions.md.

http.Response _ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
);

http.Response _failed(String message) => http.Response(
  jsonEncode({
    'subsonic-response': {
      'status': 'failed',
      'error': {'code': 50, 'message': message},
    },
  }),
  200,
);

Map<String, dynamic> _playlistJson(
  String id,
  String name, {
  int songCount = 0,
  String owner = 'alice',
}) => {
  'id': id,
  'name': name,
  'songCount': songCount,
  'duration': songCount * 60,
  'owner': owner,
  'public': false,
};

Map<String, dynamic> _songJson(String id, String title) => {
  'id': id,
  'title': title,
  'path': '$title.mp3',
  'duration': 60,
};

void main() {
  /// Builds a service over a client driven by [handler], recording every
  /// request so a test can assert what was actually sent.
  ({PlaylistsService playlists, List<Uri> requests}) build(
    http.Response Function(Uri uri) handler,
  ) {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return handler(request.url);
    });
    return (
      playlists: PlaylistsService(
        SubsonicApiService(
          serverUrl: 'https://navidrome.example.com',
          username: 'alice',
          password: 'p',
          httpClient: client,
        ),
      ),
      requests: requests,
    );
  }

  String endpointOf(Uri uri) => uri.path.split('/').last;

  group('Playlist model', () {
    test('summarises count and duration for a list subtitle', () {
      expect(
        Playlist.fromSubsonic(_playlistJson('1', 'A', songCount: 1)).summary,
        '1 track · 1 min',
      );
      expect(
        Playlist.fromSubsonic({
          ..._playlistJson('1', 'A', songCount: 12),
          'duration': 2880,
        }).summary,
        '12 tracks · 48 min',
      );
      expect(
        Playlist.fromSubsonic({
          ..._playlistJson('1', 'A', songCount: 200),
          'duration': 7200,
        }).summary,
        '200 tracks · 2h',
      );
    });

    test('only the owner may edit', () {
      final mine = Playlist.fromSubsonic(_playlistJson('1', 'A'));
      expect(mine.isEditableBy('alice'), isTrue);
      expect(mine.isEditableBy('bob'), isFalse);
    });

    test('unknown ownership is treated as editable', () {
      // The server is the real authority; hiding controls on a playlist the
      // user can actually edit would be a silent dead end.
      final unknown = Playlist.fromSubsonic({'id': '1', 'name': 'A'});
      expect(unknown.isEditableBy('alice'), isTrue);
    });
  });

  group('load', () {
    test('lists playlists', () async {
      final (:playlists, :requests) = build(
        (_) => _ok({
          'playlists': {
            'playlist': [
              _playlistJson('1', 'Roadtrip', songCount: 3),
              _playlistJson('2', 'Focus', songCount: 9),
            ],
          },
        }),
      );

      await playlists.load();

      expect(requests.map(endpointOf), ['getPlaylists']);
      expect(playlists.playlists.map((p) => p.name), ['Roadtrip', 'Focus']);
      expect(playlists.isLoaded, isTrue);
    });

    test('a single playlist is normalized into a list', () async {
      final (:playlists, requests: _) = build(
        (_) => _ok({
          'playlists': {'playlist': _playlistJson('1', 'Only')},
        }),
      );

      await playlists.load();

      expect(playlists.playlists.map((p) => p.id), ['1']);
    });

    test('no playlists still counts as loaded', () async {
      final (:playlists, requests: _) = build((_) => _ok({'playlists': {}}));

      await playlists.load();

      expect(playlists.playlists, isEmpty);
      expect(playlists.isLoaded, isTrue);
      expect(playlists.error, isNull);
    });

    test('a failure is reported, not thrown', () async {
      final (:playlists, requests: _) = build((_) => _failed('nope'));

      await playlists.load();

      expect(playlists.error, contains('Could not load playlists'));
      expect(playlists.isLoaded, isFalse);
    });

    test('logged out, load is a no-op', () async {
      final playlists = PlaylistsService(null);
      await playlists.load();
      expect(playlists.playlists, isEmpty);
      expect(playlists.error, isNull);
    });
  });

  group('loadTracks', () {
    test('fetches contents in playlist order', () async {
      final (:playlists, :requests) = build(
        (_) => _ok({
          'playlist': {
            ..._playlistJson('1', 'Roadtrip', songCount: 2),
            'entry': [_songJson('a', 'First'), _songJson('b', 'Second')],
          },
        }),
      );

      await playlists.loadTracks('1');

      expect(requests.map(endpointOf), ['getPlaylist']);
      expect(playlists.tracksOf('1')!.map((t) => t.id), ['a', 'b']);
    });

    test('an empty playlist reads as empty, not as unfetched', () async {
      final (:playlists, requests: _) = build(
        (_) => _ok({'playlist': _playlistJson('1', 'Empty')}),
      );

      await playlists.loadTracks('1');

      expect(playlists.tracksOf('1'), isEmpty);
      expect(playlists.tracksOf('nope'), isNull);
    });

    test('a second open does not refetch, but force does', () async {
      final (:playlists, :requests) = build(
        (_) => _ok({
          'playlist': {
            ..._playlistJson('1', 'Roadtrip'),
            'entry': [_songJson('a', 'First')],
          },
        }),
      );

      await playlists.loadTracks('1');
      await playlists.loadTracks('1');
      expect(requests.length, 1);

      await playlists.loadTracks('1', force: true);
      expect(requests.length, 2);
    });
  });

  group('create', () {
    test('sends the name and seeds it with song ids', () async {
      final (:playlists, :requests) = build(
        (uri) => endpointOf(uri) == 'getPlaylists'
            ? _ok({
                'playlists': {
                  'playlist': [_playlistJson('9', 'Roadtrip', songCount: 2)],
                },
              })
            : _ok({}),
      );

      final ok = await playlists.create(
        'Roadtrip',
        tracks: [
          sampleTrack(id: 'a'),
          sampleTrack(id: 'b'),
        ],
      );

      expect(ok, isTrue);
      final create = requests.firstWhere(
        (u) => endpointOf(u) == 'createPlaylist',
      );
      expect(create.queryParameters['name'], 'Roadtrip');
      // Repeated params, which is how Subsonic takes a list.
      expect(create.queryParametersAll['songId'], ['a', 'b']);
      // The list is re-read rather than patched locally.
      expect(requests.map(endpointOf), contains('getPlaylists'));
      expect(playlists.playlists.single.name, 'Roadtrip');
    });

    test('an empty playlist sends no songId at all', () async {
      final (:playlists, :requests) = build(
        (uri) => endpointOf(uri) == 'getPlaylists'
            ? _ok({'playlists': {}})
            : _ok({}),
      );

      await playlists.create('Empty');

      final create = requests.firstWhere(
        (u) => endpointOf(u) == 'createPlaylist',
      );
      expect(create.queryParameters, isNot(contains('songId')));
    });

    test('a rejected create reports and does not claim success', () async {
      final (:playlists, requests: _) = build((_) => _failed('read-only'));

      final ok = await playlists.create('Nope');

      expect(ok, isFalse);
      expect(playlists.error, contains('Could not create playlist'));
    });
  });

  group('addTracks', () {
    test('adds by song id and re-reads the playlist', () async {
      final (:playlists, :requests) = build(
        (uri) => endpointOf(uri) == 'getPlaylist'
            ? _ok({
                'playlist': {
                  ..._playlistJson('1', 'Roadtrip', songCount: 2),
                  'entry': [_songJson('a', 'First'), _songJson('b', 'Second')],
                },
              })
            : _ok({}),
      );

      final ok = await playlists.addTracks('1', [sampleTrack(id: 'b')]);

      expect(ok, isTrue);
      final update = requests.firstWhere(
        (u) => endpointOf(u) == 'updatePlaylist',
      );
      expect(update.queryParameters['playlistId'], '1');
      expect(update.queryParametersAll['songIdToAdd'], ['b']);
      // Re-read, so an open detail view and the song count are correct.
      expect(requests.map(endpointOf), contains('getPlaylist'));
      expect(playlists.tracksOf('1')!.map((t) => t.id), ['a', 'b']);
    });

    test('adding nothing is a no-op', () async {
      final (:playlists, :requests) = build((_) => _ok({}));

      final ok = await playlists.addTracks('1', const []);

      expect(ok, isFalse);
      expect(requests, isEmpty);
    });

    test('a rejected add reports it', () async {
      final (:playlists, requests: _) = build((_) => _failed('not yours'));

      final ok = await playlists.addTracks('1', [sampleTrack(id: 'b')]);

      expect(ok, isFalse);
      expect(playlists.error, contains('Could not add to playlist'));
    });
  });

  group('rename and delete', () {
    test('rename sends the new name and re-lists', () async {
      final (:playlists, :requests) = build(
        (uri) => endpointOf(uri) == 'getPlaylists'
            ? _ok({
                'playlists': {'playlist': _playlistJson('1', 'Renamed')},
              })
            : _ok({}),
      );

      final ok = await playlists.rename('1', 'Renamed');

      expect(ok, isTrue);
      final update = requests.firstWhere(
        (u) => endpointOf(u) == 'updatePlaylist',
      );
      expect(update.queryParameters['name'], 'Renamed');
      expect(playlists.playlists.single.name, 'Renamed');
    });

    test('delete drops it and its cached tracks', () async {
      var listed = false;
      final (:playlists, :requests) = build((uri) {
        if (endpointOf(uri) == 'getPlaylist') {
          return _ok({
            'playlist': {
              ..._playlistJson('1', 'Roadtrip'),
              'entry': [_songJson('a', 'First')],
            },
          });
        }
        if (endpointOf(uri) == 'getPlaylists') {
          // Empty once the delete has happened.
          final body = listed ? {'playlists': {}} : {'playlists': {}};
          listed = true;
          return _ok(body);
        }
        return _ok({});
      });

      await playlists.loadTracks('1');
      expect(playlists.tracksOf('1'), isNotNull);

      final ok = await playlists.delete('1');

      expect(ok, isTrue);
      expect(requests.map(endpointOf), contains('deletePlaylist'));
      expect(playlists.tracksOf('1'), isNull, reason: 'cached tracks dropped');
      expect(playlists.playlists, isEmpty);
    });

    test('a rejected delete reports it', () async {
      final (:playlists, requests: _) = build((_) => _failed('not yours'));

      final ok = await playlists.delete('1');

      expect(ok, isFalse);
      expect(playlists.error, contains('Could not delete playlist'));
    });
  });
}
