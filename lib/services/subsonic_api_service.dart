import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/folder.dart';
import '../models/subsonic_json.dart';
import '../models/playlist.dart';
import 'library_browser.dart';
import 'playback_reporter.dart';
import 'stream_url_resolver.dart';

class SubsonicApiException implements Exception {
  final String message;
  final int? code;

  SubsonicApiException(this.message, [this.code]);

  @override
  String toString() => message;
}

class SubsonicApiService
    implements StreamUrlResolver, PlaybackReporter, LibraryBrowser {
  final String serverUrl;
  final String username;
  final String password;

  static const String _apiVersion = '1.16.1';

  /// Sent as Subsonic's `c` param on every request. This is the name the
  /// server shows for the client — the server's "now playing" panel and play
  /// history both display it — so it is the app's real name, not an
  /// identifier. Spaces are fine; it is URI-encoded like any other param.
  static const String _clientName = 'Anywhere Music Player';
  static const _saltChars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static const int _saltLength = 12;
  static const Duration _httpTimeout = Duration(seconds: 15);

  final _random = Random.secure();
  final http.Client _httpClient;

  /// [serverUrl] with any trailing slash stripped, computed once instead of
  /// at every call site that builds a URL.
  final String _baseUrl;

  SubsonicApiService({
    required this.serverUrl,
    required this.username,
    required this.password,
    // Test-only seam: production call sites never pass this, so behavior is
    // unchanged (a real http.Client is still created by default).
    @visibleForTesting http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client(),
       _baseUrl = serverUrl.endsWith('/')
           ? serverUrl.substring(0, serverUrl.length - 1)
           : serverUrl;

  /// Generate a random salt string.
  String _generateSalt() {
    return List.generate(
      _saltLength,
      (_) => _saltChars[_random.nextInt(_saltChars.length)],
    ).join();
  }

  /// Compute Subsonic auth token: md5(password + salt).
  String _computeToken(String salt) {
    final bytes = utf8.encode('$password$salt');
    return md5.convert(bytes).toString();
  }

  /// Build auth query parameters for a Subsonic API request.
  Map<String, String> _authParams() {
    final salt = _generateSalt();
    final token = _computeToken(salt);
    return {
      'u': username,
      't': token,
      's': salt,
      'v': _apiVersion,
      'c': _clientName,
      'f': 'json',
    };
  }

  /// Build a full URL string with auth params (for embedding in stream/cover URLs).
  String _authQueryString() {
    final params = _authParams();
    return params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// Build the full URI for a Subsonic API endpoint.
  ///
  /// [extraParams] values may be a `String` or a `List<String>`; a list becomes
  /// a *repeated* query parameter (`songId=a&songId=b`), which is how Subsonic
  /// expresses multi-valued arguments like `songId` and `songIdToAdd`. `Uri`
  /// handles that natively for `Iterable<String>` values.
  Uri _buildUri(String endpoint, [Map<String, dynamic>? extraParams]) {
    final params = <String, dynamic>{..._authParams()};
    if (extraParams != null) {
      params.addAll(extraParams);
    }
    return Uri.parse(
      '$_baseUrl/rest/$endpoint',
    ).replace(queryParameters: params);
  }

  /// Build a stream URL for a song (with auth params baked in).
  ///
  /// Always requests the original file. Android wraps this URL in
  /// [LockCachingAudioSource] so ExoPlayer seeks against a local byte-range
  /// cache instead of the server's live transcoder output.
  @override
  String buildStreamUrl(String songId) {
    return '$_baseUrl/rest/stream?id=$songId&format=raw&estimateContentLength=true&${_authQueryString()}';
  }

  /// Build a cover art URL (with auth params baked in).
  @override
  String buildCoverArtUrl(String coverArtId, {int? size}) {
    final sizeParam = size != null ? '&size=$size' : '';
    return '$_baseUrl/rest/getCoverArt?id=$coverArtId$sizeParam&${_authQueryString()}';
  }

  /// Perform an HTTP GET with timeout.
  Future<http.Response> _get(Uri uri) async {
    try {
      return await _httpClient.get(uri).timeout(_httpTimeout);
    } on Exception catch (e) {
      throw SubsonicApiException('Network request failed: $e');
    }
  }

  /// Parse a Subsonic JSON response and return the inner response object.
  /// Throws [SubsonicApiException] on errors.
  Map<String, dynamic> _parseResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw SubsonicApiException(
        'HTTP error ${response.statusCode}',
        response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final subsonicResponse = data['subsonic-response'] as Map<String, dynamic>?;

    if (subsonicResponse == null) {
      throw SubsonicApiException('Invalid Subsonic response format');
    }

    final status = subsonicResponse['status'] as String?;
    if (status != 'ok') {
      final error = subsonicResponse['error'] as Map<String, dynamic>?;
      final message = error?['message'] as String? ?? 'Unknown Subsonic error';
      final code = error?['code'] as int?;
      throw SubsonicApiException(message, code);
    }

    return subsonicResponse;
  }

  /// Build [endpoint]'s URI, GET it, and parse the Subsonic envelope — the
  /// shape every read endpoint below shares. Normalizes errors the same way
  /// everywhere: a [SubsonicApiException] passes through unchanged, anything
  /// else is wrapped with [failureContext] so a caller never has to remember
  /// to add that guard itself.
  Future<Map<String, dynamic>> _request(
    String endpoint,
    Map<String, dynamic>? params,
    String failureContext,
  ) async {
    try {
      final uri = _buildUri(endpoint, params);
      final response = await _get(uri);
      return _parseResponse(response);
    } catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('$failureContext: $e');
    }
  }

  // -------- Playlists --------

  /// Every playlist visible to the current user (their own, plus public ones).
  Future<List<Playlist>> getPlaylists() async {
    final data = await _request(
      'getPlaylists',
      null,
      'Could not load playlists',
    );
    final playlists = data['playlists'] as Map<String, dynamic>?;
    return _parseAll(playlists?['playlist'], Playlist.fromSubsonic);
  }

  /// One playlist with its tracks, in playlist order.
  ///
  /// Order matters beyond display: Subsonic removes tracks by *position*, so
  /// the indices a caller derives from this list are what an edit is built
  /// from. See docs/decisions.md.
  Future<({Playlist playlist, List<Track> tracks})> getPlaylist(
    String playlistId,
  ) async {
    final data = await _request('getPlaylist', {
      'id': playlistId,
    }, 'Could not load playlist');
    final json = data['playlist'] as Map<String, dynamic>?;
    if (json == null) {
      throw SubsonicApiException('Playlist $playlistId not found');
    }
    return (
      playlist: Playlist.fromSubsonic(json),
      tracks: _parseAll(json['entry'], Track.fromSubsonic),
    );
  }

  /// Create a playlist called [name], optionally seeded with [songIds].
  ///
  /// Returns the new playlist. Subsonic's response for this is inconsistent
  /// across servers — some echo the playlist, some return an empty envelope —
  /// so a caller that needs it should re-list rather than trust the return.
  Future<Playlist?> createPlaylist(
    String name, {
    List<String> songIds = const [],
  }) async {
    final data = await _request('createPlaylist', {
      'name': name,
      if (songIds.isNotEmpty) 'songId': songIds,
    }, 'Could not create playlist');
    final json = data['playlist'] as Map<String, dynamic>?;
    return json == null ? null : Playlist.fromSubsonic(json);
  }

  /// Append [songIds] to an existing playlist.
  ///
  /// Adding is by **song id**, so unlike removal it needs no knowledge of the
  /// playlist's current order and is safe against concurrent edits.
  Future<void> addToPlaylist(String playlistId, List<String> songIds) async {
    if (songIds.isEmpty) return;
    await _request('updatePlaylist', {
      'playlistId': playlistId,
      'songIdToAdd': songIds,
    }, 'Could not add to playlist');
  }

  /// Remove the tracks at [indexes] from a playlist.
  ///
  /// **Zero-based**. The Subsonic spec does not state the base, so this is a
  /// behavioural dependency on the server, not a documented one — it was
  /// confirmed against Navidrome (`core/playlists/playlists.go` converts
  /// with `idx + 1` internally) and carried over to Gonic unchanged. See
  /// docs/decisions.md.
  ///
  /// Positions refer to the playlist's *current server-side* order, so a
  /// caller must re-read immediately beforehand rather than trusting a cached
  /// list. [PlaylistsService.removeTrack] is the safe way in.
  Future<void> removeFromPlaylist(String playlistId, List<int> indexes) async {
    if (indexes.isEmpty) return;
    await _request('updatePlaylist', {
      'playlistId': playlistId,
      'songIndexToRemove': [for (final i in indexes) i.toString()],
    }, 'Could not remove from playlist');
  }

  /// Rename a playlist.
  Future<void> renamePlaylist(String playlistId, String name) async {
    await _request('updatePlaylist', {
      'playlistId': playlistId,
      'name': name,
    }, 'Could not rename playlist');
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _request('deletePlaylist', {
      'id': playlistId,
    }, 'Could not delete playlist');
  }

  /// Mark [songId] as a favourite (Subsonic "starred").
  ///
  /// Songs only. Folders in this app are *virtual* — their id is the library
  /// path (see LibraryScanner.toFolder), not a Subsonic album id — so there is
  /// nothing to star for an album or artist here. See docs/decisions.md.
  Future<void> star(String songId) async {
    await _request('star', {'id': songId}, 'Could not add to favourites');
  }

  /// Remove [songId] from favourites.
  Future<void> unstar(String songId) async {
    await _request('unstar', {
      'id': songId,
    }, 'Could not remove from favourites');
  }

  /// Every starred song, newest first as the server orders them.
  ///
  /// Uses `getStarred2` (the tag-based variant); the albums and artists it also
  /// returns are ignored — see [star] for why.
  Future<List<Track>> getStarredSongs() async {
    final data = await _request(
      'getStarred2',
      null,
      'Could not load favourites',
    );

    final starred = data['starred2'] as Map<String, dynamic>?;
    return _parseAll(starred?['song'], Track.fromSubsonic);
  }

  /// Announce that [songId] is playing now (`submission=false`).
  ///
  /// Feeds the server's "now playing" panel only — it does not count as a
  /// play. See [scrobble] for that.
  @override
  Future<void> nowPlaying(String songId) async {
    await _request('scrobble', {
      'id': songId,
      'submission': 'false',
    }, 'Now-playing report failed');
  }

  /// Record a completed listen of [songId] (`submission=true`), which is what
  /// increments the server's play count.
  ///
  /// [startedAt] is sent as `time` in milliseconds since the epoch — Subsonic
  /// 1.8+, and understood by both Navidrome and Gonic. It is when the listen
  /// *began*, so a play submitted partway through a long track is still timed
  /// correctly.
  /// Omitting it lets the server stamp the play at receipt instead.
  @override
  Future<void> scrobble(String songId, {DateTime? startedAt}) async {
    await _request('scrobble', {
      'id': songId,
      'submission': 'true',
      if (startedAt != null)
        'time': startedAt.millisecondsSinceEpoch.toString(),
    }, 'Scrobble failed');
  }

  /// Ping the server to verify credentials.
  /// Returns true if auth succeeds, throws on failure.
  Future<bool> ping() async {
    if (kDebugMode) debugPrint('Subsonic ping: $_baseUrl/rest/ping');
    await _request('ping', null, 'Connection failed');
    return true;
  }

  /// Search for songs, albums, and artists using search3.
  Future<({List<Track> songs, List<Folder> albums})> search3(
    String query, {
    int songCount = 50,
    int albumCount = 20,
    int artistCount = 20,
  }) async {
    final data = await _request('search3', {
      'query': query,
      'songCount': songCount.toString(),
      'albumCount': albumCount.toString(),
      'artistCount': artistCount.toString(),
    }, 'Search failed');

    final searchResult = data['searchResult3'] as Map<String, dynamic>?;
    return (
      songs: _parseAll(searchResult?['song'], Track.fromSubsonic),
      albums: _parseAll(searchResult?['album'], Folder.fromSubsonic),
    );
  }

  // -------- Browsing by folder --------

  /// The server's configured music folders.
  ///
  /// Gonic exposes every `-music-path` it was given as one of these, so a
  /// library built on a single path yields a single entry.
  @override
  Future<List<({String id, String name})>> getMusicFolders() async {
    final data = await _request(
      'getMusicFolders',
      null,
      'Could not load music folders',
    );
    final folders = data['musicFolders'] as Map<String, dynamic>?;
    return _dirEntries(folders?['musicFolder']);
  }

  /// The top level of a music folder: its immediate child directories, plus
  /// any songs sitting loose at the music-folder root.
  ///
  /// `getIndexes` buckets the top-level directories alphabetically
  /// (`index[].artist[]`). That grouping is a display convenience for
  /// Subsonic's own browser and is flattened away here — the folder tree this
  /// app shows is the server's, not an alphabet.
  @override
  Future<
    ({
      List<({String id, String name})> directories,
      List<Map<String, dynamic>> songs,
    })
  >
  getIndexes({String? musicFolderId}) async {
    final params = <String, dynamic>{};
    if (musicFolderId != null) params['musicFolderId'] = musicFolderId;
    final data = await _request(
      'getIndexes',
      params,
      'Could not load the library index',
    );

    final indexes = data['indexes'] as Map<String, dynamic>?;
    if (indexes == null) {
      return (
        directories: <({String id, String name})>[],
        songs: <Map<String, dynamic>>[],
      );
    }

    final directories = <({String id, String name})>[];
    for (final bucket in subsonicList(indexes['index'])) {
      directories.addAll(
        _dirEntries((bucket as Map<String, dynamic>)['artist']),
      );
    }

    return (directories: directories, songs: _songEntries(indexes['child']));
  }

  /// One directory's immediate children, split into subdirectories and songs.
  @override
  Future<
    ({
      List<({String id, String name})> directories,
      List<Map<String, dynamic>> songs,
    })
  >
  getMusicDirectory(String id) async {
    final data = await _request('getMusicDirectory', {
      'id': id,
    }, 'Could not load folder');

    final directory = data['directory'] as Map<String, dynamic>?;

    final directories = <({String id, String name})>[];
    final songs = <Map<String, dynamic>>[];
    for (final child in subsonicList(directory?['child'])) {
      final json = child as Map<String, dynamic>;
      if (json['isDir'] == true) {
        final childId = json['id']?.toString();
        if (childId == null) continue;
        directories.add((
          id: childId,
          name:
              json['title'] as String? ?? json['name'] as String? ?? childId,
        ));
      } else {
        songs.add(json);
      }
    }

    return (directories: directories, songs: songs);
  }

  /// Every model list in a response: normalize Subsonic's single-element
  /// collapse, then parse each entry. [value] is the raw field — a list, a
  /// bare object, or absent.
  static List<T> _parseAll<T>(
    dynamic value,
    T Function(Map<String, dynamic> json) parse,
  ) => [
    for (final item in subsonicList(value)) parse(item as Map<String, dynamic>),
  ];

  /// The `(id, name)` pairs in a browse response's directory list. Entries
  /// without an id are skipped — there is nothing to fetch for them.
  static List<({String id, String name})> _dirEntries(dynamic value) {
    final entries = <({String id, String name})>[];
    for (final item in subsonicList(value)) {
      final json = item as Map<String, dynamic>;
      final id = json['id']?.toString();
      if (id == null) continue;
      entries.add((
        id: id,
        name: json['name'] as String? ?? json['title'] as String? ?? id,
      ));
    }
    return entries;
  }

  /// The non-directory children of a browse response's child list.
  static List<Map<String, dynamic>> _songEntries(dynamic value) {
    final songs = <Map<String, dynamic>>[];
    for (final item in subsonicList(value)) {
      final json = item as Map<String, dynamic>;
      if (json['isDir'] != true) songs.add(json);
    }
    return songs;
  }

  /// Dispose the HTTP client.
  void dispose() {
    _httpClient.close();
  }
}
