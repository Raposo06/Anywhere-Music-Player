import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/services/playlists_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

/// A stand-in Subsonic server for the playlist screens.
///
/// Holds playlists and their tracks in memory and answers the five playlist
/// endpoints against that state, so a screen test can assert on what the user
/// ends up seeing rather than on which requests were sent. Mutations are
/// applied for real — `removeAt` uses the same **zero-based** index Navidrome
/// does — which is what makes "tap remove, see the row go" meaningful.
class FakePlaylistServer {
  /// playlist id → (name, owner, track ids)
  final Map<String, ({String name, String owner, List<String> trackIds})>
  playlists;

  /// Every request this server answered, by endpoint name.
  final List<String> calls = [];

  /// Playlist ids the server reports as `readonly` — Navidrome's OpenSubsonic
  /// flag, which is how a smart playlist (`.nsp`) announces that it cannot be
  /// edited even by its owner.
  final Set<String> readonlyIds = {};

  /// When set, every write fails with this Subsonic error message.
  String? failWrites;

  var _nextId = 100;

  FakePlaylistServer({
    Map<String, ({String name, String owner, List<String> trackIds})>?
    playlists,
  }) : playlists = playlists ?? {};

  /// The service under test, wired to this server.
  PlaylistsService service({String username = 'alice'}) => PlaylistsService(
    SubsonicApiService(
      serverUrl: 'https://navidrome.example.com',
      username: username,
      password: 'p',
      httpClient: _client(),
    ),
  );

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

  Map<String, dynamic> _json(String id, {bool withEntries = false}) {
    final p = playlists[id]!;
    return {
      'id': id,
      'name': p.name,
      'songCount': p.trackIds.length,
      'duration': p.trackIds.length * 60,
      'owner': p.owner,
      'public': false,
      if (readonlyIds.contains(id)) 'readonly': true,
      if (withEntries)
        'entry': [
          for (final t in p.trackIds)
            {'id': t, 'title': 'Song $t', 'path': '$t.mp3', 'duration': 60},
        ],
    };
  }

  MockClient _client() => MockClient((request) async {
    final uri = request.url;
    final endpoint = uri.path.split('/').last;
    calls.add(endpoint);
    final q = uri.queryParameters;
    final all = uri.queryParametersAll;

    switch (endpoint) {
      case 'getPlaylists':
        return _ok({
          'playlists': {
            'playlist': [for (final id in playlists.keys) _json(id)],
          },
        });

      case 'getPlaylist':
        final id = q['id']!;
        if (!playlists.containsKey(id)) return _failed('not found');
        return _ok({'playlist': _json(id, withEntries: true)});

      case 'createPlaylist':
        if (failWrites case final message?) return _failed(message);
        final id = q['playlistId'] ?? '${_nextId++}';
        // Navidrome replaces contents when a playlistId is given.
        playlists[id] = (
          name: q['name'] ?? playlists[id]?.name ?? 'Untitled',
          owner: 'alice',
          trackIds: [...?all['songId']],
        );
        return _ok({'playlist': _json(id)});

      case 'updatePlaylist':
        if (failWrites case final message?) return _failed(message);
        final id = q['playlistId']!;
        final current = playlists[id]!;
        final ids = [...current.trackIds];
        // Zero-based, highest first, matching Navidrome.
        final remove =
            (all['songIndexToRemove'] ?? const []).map(int.parse).toList()
              ..sort((a, b) => b - a);
        for (final i in remove) {
          if (i >= 0 && i < ids.length) ids.removeAt(i);
        }
        ids.addAll(all['songIdToAdd'] ?? const []);
        playlists[id] = (
          name: q['name'] ?? current.name,
          owner: current.owner,
          trackIds: ids,
        );
        return _ok({});

      case 'deletePlaylist':
        if (failWrites case final message?) return _failed(message);
        playlists.remove(q['id']);
        return _ok({});

      default:
        return _ok({});
    }
  });
}
