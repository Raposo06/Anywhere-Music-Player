import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

/// [path]'s last segment, extension stripped — LibraryScanner.scan() uses
/// the native-API `title` field verbatim as Track.title, so a fixture whose
/// title still carried ".mp3" would make every title assertion wrong.
String _titleFromPath(String path) {
  final base = path.split('/').last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

Map<String, dynamic> nativeApiSong({
  required String id,
  required String path,
  String? coverArtId,
}) => {
  'id': id,
  'path': path,
  'title': _titleFromPath(path),
  'coverArtId': coverArtId,
  'duration': 120,
  'size': 1000,
};

/// A [LibraryScanner] wired to a fake Navidrome native-API server that
/// returns [songs] — see LibraryScanner.scan()/getAllSongsNativeApi(). Call
/// `scan()` wrapped in `tester.runAsync(...)` before pumping the widget (or,
/// for scans a widget's own initState triggers, pump once then wrap the wait
/// in `tester.runAsync`) — scan() spawns a real isolate via compute(), which
/// testWidgets()'s fake-async zone never resolves under plain pump/pumpAndSettle.
/// See test/support/pump_helpers.dart's `waitForAsyncWork`.
LibraryScanner scannerWithSongs(List<Map<String, dynamic>> songs) {
  final client = MockClient((request) async {
    if (request.method == 'POST' && request.url.path == '/auth/login') {
      return http.Response(jsonEncode({'token': 'fake-jwt'}), 200);
    }
    if (request.method == 'GET' && request.url.path == '/api/song') {
      final start = int.parse(request.url.queryParameters['_start']!);
      final page = songs.skip(start).take(500).toList();
      return http.Response(jsonEncode(page), 200);
    }
    return http.Response('not found', 404);
  });

  return LibraryScanner(SubsonicApiService(
    serverUrl: 'https://navidrome.example.com',
    username: 'alice',
    password: 'secret',
    httpClient: client,
  ));
}
