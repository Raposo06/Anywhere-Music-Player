import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/folder.dart';
import '../models/playlist.dart';
import 'playback_reporter.dart';
import 'stream_url_resolver.dart';

class SubsonicApiException implements Exception {
  final String message;
  final int? code;

  SubsonicApiException(this.message, [this.code]);

  @override
  String toString() => message;
}

class SubsonicApiService implements StreamUrlResolver, PlaybackReporter {
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

  /// Directories fetched in parallel by [getAllTracksByFolder]. Enough to
  /// keep a scan from being latency-bound, low enough not to look like a
  /// burst to a small self-hosted server.
  static const int _walkConcurrency = 8;

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
    final list = playlists?['playlist'];
    if (list == null) return <Playlist>[];
    final items = list is List ? list : [list];
    return [
      for (final item in items)
        Playlist.fromSubsonic(item as Map<String, dynamic>),
    ];
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
    final entries = json['entry'];
    final items = entries == null
        ? const []
        : (entries is List ? entries : [entries]);
    return (
      playlist: Playlist.fromSubsonic(json),
      tracks: [
        for (final item in items)
          Track.fromSubsonic(item as Map<String, dynamic>),
      ],
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
    if (starred == null) return <Track>[];

    final songList = starred['song'];
    if (songList == null) return <Track>[];

    // Subsonic collapses a single-element list into a bare object — same
    // normalization search3 does.
    final items = songList is List ? songList : [songList];
    return [
      for (final item in items)
        Track.fromSubsonic(item as Map<String, dynamic>),
    ];
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
    if (searchResult == null) {
      return (songs: <Track>[], albums: <Folder>[]);
    }

    // Parse songs
    final songList = searchResult['song'];
    final songs = <Track>[];
    if (songList != null) {
      final items = songList is List ? songList : [songList];
      for (final item in items) {
        songs.add(Track.fromSubsonic(item as Map<String, dynamic>));
      }
    }

    // Parse albums as folders
    final albumList = searchResult['album'];
    final albums = <Folder>[];
    if (albumList != null) {
      final items = albumList is List ? albumList : [albumList];
      for (final item in items) {
        albums.add(Folder.fromSubsonic(item as Map<String, dynamic>));
      }
    }

    return (songs: songs, albums: albums);
  }

  // -------- Browsing by folder --------

  /// The server's configured music folders.
  ///
  /// Gonic exposes every `-music-path` it was given as one of these, so a
  /// library built on a single path yields a single entry.
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
    for (final bucket in _asList(indexes['index'])) {
      directories.addAll(
        _dirEntries((bucket as Map<String, dynamic>)['artist']),
      );
    }

    return (directories: directories, songs: _songEntries(indexes['child']));
  }

  /// One directory's immediate children, split into subdirectories and songs.
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
    for (final child in _asList(directory?['child'])) {
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

  /// Walk the server's real directory tree and return every song under it.
  /// This is the library scan.
  ///
  /// Each [Track] carries a library-relative path (`Anime/Naruto/01 -
  /// Opening.flac`), which is what [LibraryScanner] rebuilds the browsable
  /// tree from. It is read from the song's own `path` field, and only
  /// synthesized from the descent when the server omits it or sends an
  /// absolute one.
  ///
  /// This used to be the other way round. The walk is only as folder-shaped
  /// as `getIndexes` is: Gonic answered it with a tag-shaped artist index
  /// (`5050/One Piece/…`, `[Unknown Artist]/[Unknown Album]/…`), and the
  /// synthesized path faithfully reproduced that instead of the on-disk tree
  /// the folder browser exists to show. The song's `path` is the on-disk
  /// tree. See docs/decisions.md.
  ///
  /// Walked breadth-first, [_walkConcurrency] directories per round trip. A
  /// folder-native server answers one directory per request, so a library of
  /// a few thousand directories is a few thousand requests — issuing them
  /// strictly one after another is what would make a scan feel slow.
  Future<List<Track>> getAllTracksByFolder({
    void Function(int songsSoFar)? onProgress,
  }) async {
    final musicFolders = await getMusicFolders();

    // With one music folder its name is left out of the path, so paths stay
    // relative to the music root — the shape the folder tree, the on-disk
    // cache and the now-playing folder line were all built around. With
    // several, the name becomes the top-level segment that tells them apart.
    final prefixWithFolderName = musicFolders.length > 1;

    final tracks = <Track>[];
    // Every directory id this walk has already queued. A server that reports a
    // directory as its own descendant — or the same shared directory under two
    // music folders — would otherwise loop forever, or at best duplicate every
    // track under it. Nothing observed does this; the walk is recursive over
    // data from the network, which is reason enough not to trust it to
    // terminate on its own.
    final visited = <String>{};
    var level = <({String id, String path, String root})>[];

    for (final folder in musicFolders) {
      final root = prefixWithFolderName ? folder.name : '';
      final top = await getIndexes(musicFolderId: folder.id);
      tracks.addAll(_tracksIn(top.songs, root, root));
      for (final dir in top.directories) {
        if (!visited.add(dir.id)) continue;
        level.add((id: dir.id, path: _joinPath(root, dir.name), root: root));
      }
    }

    while (level.isNotEmpty) {
      final next = <({String id, String path, String root})>[];
      for (var i = 0; i < level.length; i += _walkConcurrency) {
        final batch = level.skip(i).take(_walkConcurrency);
        final listings = await Future.wait([
          for (final entry in batch)
            getMusicDirectory(
              entry.id,
            ).then((contents) => (entry: entry, contents: contents)),
        ]);
        for (final listing in listings) {
          tracks.addAll(_tracksIn(
            listing.contents.songs,
            listing.entry.path,
            listing.entry.root,
          ));
          for (final dir in listing.contents.directories) {
            if (!visited.add(dir.id)) continue;
            next.add((
              id: dir.id,
              path: _joinPath(listing.entry.path, dir.name),
              root: listing.entry.root,
            ));
          }
        }
        onProgress?.call(tracks.length);
      }
      level = next;
    }

    // Path order — what the previous whole-library fetch sorted by, and what
    // every list in the UI still expects. The walk finishes breadth-first, so
    // without this the flat list interleaves depths.
    tracks.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return tracks;
  }

  /// Subsonic collapses a single-element list into a bare object, so every
  /// list in a browse response has to be read through this.
  static List<dynamic> _asList(dynamic value) {
    if (value == null) return const [];
    return value is List ? value : [value];
  }

  /// The `(id, name)` pairs in a browse response's directory list. Entries
  /// without an id are skipped — there is nothing to fetch for them.
  static List<({String id, String name})> _dirEntries(dynamic value) {
    final entries = <({String id, String name})>[];
    for (final item in _asList(value)) {
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
    for (final item in _asList(value)) {
      final json = item as Map<String, dynamic>;
      if (json['isDir'] != true) songs.add(json);
    }
    return songs;
  }

  static List<Track> _tracksIn(
    List<Map<String, dynamic>> songs,
    String dirPath,
    String root,
  ) => [
    for (final song in songs)
      Track.fromSubsonic(song, pathOverride: _pathOf(song, dirPath, root)),
  ];

  /// The library-relative path a track is filed under.
  ///
  /// Prefers the server's own `path`, because on a folder-native server that
  /// *is* the on-disk tree — the thing the folder browser exists to show — and
  /// it stays correct however `getIndexes` chooses to shape its index. [root]
  /// is the music folder's name, non-empty only when there's more than one
  /// folder to tell apart; the server's path is relative to its own music
  /// folder, so it needs that prefix to stay unambiguous.
  ///
  /// Falls back to the walked path in the two cases where the server's is
  /// unusable:
  ///
  /// - **absent or empty** — the Subsonic spec doesn't require `path`;
  /// - **absolute** (`/mnt/music/…`, `C:\Music\…`) — a filesystem path whose
  ///   library root this client can't know, so there is nothing safe to strip.
  ///   Navidrome sent these, which is why the walk existed in the first place.
  static String _pathOf(
    Map<String, dynamic> song,
    String dirPath,
    String root,
  ) {
    final serverPath = (song['path'] as String?)?.replaceAll('\\', '/').trim();
    if (serverPath != null && serverPath.isNotEmpty && !_isAbsolute(serverPath)) {
      final cleaned = serverPath
          .split('/')
          .where((seg) => seg.isNotEmpty && seg != '.')
          .join('/');
      if (cleaned.isNotEmpty) return _joinPath(root, cleaned);
    }
    return _joinPath(dirPath, _fileNameOf(song));
  }

  /// True for a path rooted at a filesystem, POSIX (`/music/x`) or Windows
  /// (`C:/music/x`, `//server/share/x`) — separators already normalised to `/`.
  static bool _isAbsolute(String path) {
    if (path.startsWith('/')) return true;
    return path.length >= 2 &&
        path[1] == ':' &&
        RegExp(r'^[A-Za-z]$').hasMatch(path[0]);
  }

  static String _joinPath(String parent, String child) =>
      parent.isEmpty ? child : '$parent/$child';

  /// The song's own file name, for the last segment of its synthesized path.
  /// Prefers the basename of whatever `path` the server sends, falling back to
  /// title + suffix — which a browse response always carries.
  static String _fileNameOf(Map<String, dynamic> song) {
    final serverPath = song['path'] as String?;
    if (serverPath != null && serverPath.isNotEmpty) {
      return serverPath.split('/').last;
    }
    final title = song['title'] as String? ?? song['id'].toString();
    final suffix = song['suffix'] as String?;
    return (suffix != null && suffix.isNotEmpty) ? '$title.$suffix' : title;
  }

  /// Dispose the HTTP client.
  void dispose() {
    _httpClient.close();
  }
}
