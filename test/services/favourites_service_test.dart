import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/services/favourites_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import '../support/fixtures.dart';

// Covers FavouritesService: loading the starred list, and the optimistic
// toggle — which applies locally first and rolls back if the server rejects
// it, so the heart never waits on a round trip. See docs/decisions.md.

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
      'error': {'code': 70, 'message': message},
    },
  }),
  200,
);

Map<String, dynamic> _song(String id, String title) => {
  'id': id,
  'title': title,
  'path': '$title.mp3',
  'duration': 180,
};

void main() {
  /// Builds a service over a client that answers with [handler], recording
  /// every endpoint it was asked for.
  ({FavouritesService favourites, List<String> endpoints}) build(
    http.Response Function(Uri uri) handler,
  ) {
    final endpoints = <String>[];
    final client = MockClient((request) async {
      endpoints.add(request.url.path.split('/').last);
      return handler(request.url);
    });
    return (
      favourites: FavouritesService(
        SubsonicApiService(
          serverUrl: 'https://navidrome.example.com',
          username: 'a',
          password: 'p',
          httpClient: client,
        ),
      ),
      endpoints: endpoints,
    );
  }

  group('load', () {
    test('parses starred songs and exposes them for lookup', () async {
      final (:favourites, :endpoints) = build(
        (_) => _ok({
          'starred2': {
            'song': [_song('1', 'First'), _song('2', 'Second')],
          },
        }),
      );

      await favourites.load();

      expect(endpoints, ['getStarred2']);
      expect(favourites.starred.map((t) => t.id), ['1', '2']);
      expect(favourites.isStarred('1'), isTrue);
      expect(favourites.isStarred('nope'), isFalse);
      expect(favourites.isLoaded, isTrue);
      expect(favourites.error, isNull);
    });

    test('a single starred song is normalized into a list', () async {
      // Subsonic collapses a one-element list into a bare object.
      final (:favourites, endpoints: _) = build(
        (_) => _ok({
          'starred2': {'song': _song('1', 'Only')},
        }),
      );

      await favourites.load();

      expect(favourites.starred.map((t) => t.id), ['1']);
    });

    test('no favourites yet still counts as loaded', () async {
      final (:favourites, endpoints: _) = build((_) => _ok({'starred2': {}}));

      await favourites.load();

      expect(favourites.starred, isEmpty);
      expect(favourites.isLoaded, isTrue, reason: 'empty is not "unfetched"');
      expect(favourites.error, isNull);
    });

    test('a server failure is reported, not thrown', () async {
      final (:favourites, endpoints: _) = build((_) => _failed('nope'));

      await favourites.load();

      expect(favourites.error, contains('Could not load favourites'));
      expect(favourites.isLoaded, isFalse);
    });

    test('logged out, load is a no-op', () async {
      final favourites = FavouritesService(null);

      await favourites.load();

      expect(favourites.starred, isEmpty);
      expect(favourites.error, isNull);
    });
  });

  group('toggle', () {
    test('starring applies before the server answers', () async {
      var release = false;
      final (:favourites, :endpoints) = build((_) {
        expect(
          release,
          isTrue,
          reason: 'the local state should already be updated by now',
        );
        return _ok({});
      });
      final track = sampleTrack(id: '1');

      final pending = favourites.toggle(track);
      // The heart is already filled, before the request has been answered.
      expect(favourites.isStarred('1'), isTrue);
      release = true;
      await pending;

      expect(endpoints, ['star']);
      expect(favourites.starred.map((t) => t.id), ['1']);
    });

    test('unstarring removes it and calls unstar', () async {
      final (:favourites, :endpoints) = build((uri) {
        if (uri.path.endsWith('getStarred2')) {
          return _ok({
            'starred2': {'song': _song('1', 'First')},
          });
        }
        return _ok({});
      });
      await favourites.load();
      expect(favourites.isStarred('1'), isTrue);

      await favourites.toggle(sampleTrack(id: '1'));

      expect(endpoints, ['getStarred2', 'unstar']);
      expect(favourites.isStarred('1'), isFalse);
      expect(favourites.starred, isEmpty);
    });

    test('newly starred tracks go to the top', () async {
      final (:favourites, endpoints: _) = build((uri) {
        if (uri.path.endsWith('getStarred2')) {
          return _ok({
            'starred2': {
              'song': [_song('1', 'Old'), _song('2', 'Older')],
            },
          });
        }
        return _ok({});
      });
      await favourites.load();

      await favourites.toggle(sampleTrack(id: '3'));

      expect(favourites.starred.map((t) => t.id), ['3', '1', '2']);
    });

    test('a rejected star rolls back and reports why', () async {
      final (:favourites, endpoints: _) = build((_) => _failed('read-only'));
      final track = sampleTrack(id: '1');

      await favourites.toggle(track);

      expect(favourites.isStarred('1'), isFalse, reason: 'rolled back');
      expect(favourites.starred, isEmpty);
      expect(favourites.error, contains('Could not add to favourites'));
    });

    test('a rejected unstar restores it at its original position', () async {
      final (:favourites, endpoints: _) = build((uri) {
        if (uri.path.endsWith('getStarred2')) {
          return _ok({
            'starred2': {
              'song': [
                _song('1', 'First'),
                _song('2', 'Second'),
                _song('3', 'Third'),
              ],
            },
          });
        }
        return _failed('read-only');
      });
      await favourites.load();

      await favourites.toggle(sampleTrack(id: '2'));

      expect(favourites.isStarred('2'), isTrue, reason: 'rolled back');
      // Restored in place, not promoted to the front.
      expect(favourites.starred.map((t) => t.id), ['1', '2', '3']);
      expect(favourites.error, contains('Could not remove from favourites'));
    });

    test('clearError drops the message once a screen has shown it', () async {
      final (:favourites, endpoints: _) = build((_) => _failed('nope'));
      await favourites.toggle(sampleTrack(id: '1'));
      expect(favourites.error, isNotNull);

      favourites.clearError();

      expect(favourites.error, isNull);
    });

    test('logged out, toggle is a no-op', () async {
      final favourites = FavouritesService(null);

      await favourites.toggle(sampleTrack(id: '1'));

      expect(favourites.isStarred('1'), isFalse);
      expect(favourites.error, isNull);
    });
  });
}
