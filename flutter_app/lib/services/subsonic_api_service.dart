import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/folder.dart';

class SubsonicApiException implements Exception {
  final String message;
  final int? code;

  SubsonicApiException(this.message, [this.code]);

  @override
  String toString() => message;
}

class SubsonicApiService {
  final String serverUrl;
  final String username;
  final String password;

  static const String _apiVersion = '1.16.1';
  static const String _clientName = 'AnywherePlayer';
  static const _saltChars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static const int _saltLength = 12;
  static const Duration _httpTimeout = Duration(seconds: 15);

  final _random = Random.secure();
  final http.Client _httpClient = http.Client();

  /// In-memory LRU cache for directory contents and folder listings.
  /// Key: cache key string, Value: cached response with timestamp.
  static final Map<String, _CacheEntry> _cache = {};
  static const int _maxCacheSize = 100;
  static const Duration _cacheTtl = Duration(minutes: 5);

  SubsonicApiService({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

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
    return params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  }

  /// Build the full URI for a Subsonic API endpoint.
  Uri _buildUri(String endpoint, [Map<String, String>? extraParams]) {
    final baseUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    final params = _authParams();
    if (extraParams != null) {
      params.addAll(extraParams);
    }
    return Uri.parse('$baseUrl/rest/$endpoint').replace(queryParameters: params);
  }

  /// Build a stream URL for a song (with auth params baked in).
  String buildStreamUrl(String songId) {
    final baseUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return '$baseUrl/rest/stream?id=$songId&estimateContentLength=true&${_authQueryString()}';
  }

  /// Build a cover art URL (with auth params baked in).
  String buildCoverArtUrl(String coverArtId, {int? size}) {
    final baseUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    final sizeParam = size != null ? '&size=$size' : '';
    return '$baseUrl/rest/getCoverArt?id=$coverArtId$sizeParam&${_authQueryString()}';
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

  /// Get a cached value or null if expired/missing.
  T? _getFromCache<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return entry.data as T?;
  }

  /// Store a value in the cache with LRU eviction.
  void _putInCache(String key, dynamic data) {
    if (_cache.length >= _maxCacheSize) {
      // Remove oldest entry
      final oldestKey = _cache.entries
          .reduce((a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b)
          .key;
      _cache.remove(oldestKey);
    }
    _cache[key] = _CacheEntry(data: data, timestamp: DateTime.now());
  }

  /// Invalidate all cached data.
  void clearCache() {
    _cache.clear();
  }

  /// Ping the server to verify credentials.
  /// Returns true if auth succeeds, throws on failure.
  Future<bool> ping() async {
    try {
      final uri = _buildUri('ping');
      debugPrint('Subsonic ping: ${uri.host}${uri.path}');
      final response = await _get(uri);
      _parseResponse(response);
      return true;
    } catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('Connection failed: $e');
    }
  }

  /// Get the list of top-level music folders configured in Navidrome.
  /// Returns a list of {id, name} maps.
  Future<List<Map<String, dynamic>>> getMusicFolders() async {
    try {
      final uri = _buildUri('getMusicFolders');
      final response = await _get(uri);
      final data = _parseResponse(response);

      final musicFolders = data['musicFolders'] as Map<String, dynamic>?;
      if (musicFolders == null) return [];

      final folderList = musicFolders['musicFolder'];
      if (folderList is List) {
        return folderList.cast<Map<String, dynamic>>();
      }
      if (folderList is Map<String, dynamic>) {
        return [folderList];
      }
      return [];
    } catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('Failed to get music folders: $e');
    }
  }

  /// Get the index of artists/folders for a music folder.
  /// Returns the full indexes response (artists grouped by letter).
  Future<Map<String, dynamic>> getIndexes({String? musicFolderId}) async {
    final cacheKey = 'indexes_${musicFolderId ?? 'all'}';
    final cached = _getFromCache<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    try {
      final params = <String, String>{};
      if (musicFolderId != null) params['musicFolderId'] = musicFolderId;

      final uri = _buildUri('getIndexes', params);
      final response = await _get(uri);
      final result = _parseResponse(response);
      _putInCache(cacheKey, result);
      return result;
    } catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('Failed to get indexes: $e');
    }
  }

  /// Get the contents of a music directory by ID.
  /// Returns {directory: {id, name, child: [...]}} where child items can be
  /// subdirectories (isDir=true) or songs (isDir=false).
  Future<Map<String, dynamic>> getMusicDirectory(String id) async {
    final cacheKey = 'dir_$id';
    final cached = _getFromCache<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    try {
      final uri = _buildUri('getMusicDirectory', {'id': id});
      final response = await _get(uri);
      final result = _parseResponse(response);
      _putInCache(cacheKey, result);
      return result;
    } catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('Failed to get music directory: $e');
    }
  }

  /// Get top-level folders as [Folder] objects.
  /// Uses getMusicFolders to get the root library, then getMusicDirectory
  /// to list the actual filesystem directories (not tag-based artists).
  Future<List<Folder>> getFolders({String? musicFolderId}) async {
    // Step 1: Get the root music library folder(s) from Navidrome
    final musicFolders = await getMusicFolders();
    if (musicFolders.isEmpty) return [];

    // Step 2: For each root library, get its directory contents.
    // Most Navidrome setups have a single music folder.
    final allFolders = <Folder>[];

    for (final mf in musicFolders) {
      final rootId = mf['id']?.toString();
      if (rootId == null) continue;

      try {
        final contents = await getDirectoryContents(rootId);
        allFolders.addAll(contents.folders);
        // If there are tracks at the root level, they'll be shown in the home screen
      } catch (e) {
        debugPrint('Failed to load music folder $rootId: $e');
      }
    }

    return allFolders;
  }

  /// Get top-level root tracks (songs sitting directly in the music folder root).
  Future<List<Track>> getRootTracks() async {
    final musicFolders = await getMusicFolders();
    if (musicFolders.isEmpty) return [];

    final allTracks = <Track>[];

    for (final mf in musicFolders) {
      final rootId = mf['id']?.toString();
      if (rootId == null) continue;

      try {
        final contents = await getDirectoryContents(rootId);
        allTracks.addAll(contents.tracks);
      } catch (e) {
        debugPrint('Failed to load root tracks from $rootId: $e');
      }
    }

    return allTracks;
  }

  /// Get the children of a directory as folders and tracks.
  /// Returns ({folders: [...], tracks: [...]}).
  Future<({List<Folder> folders, List<Track> tracks})> getDirectoryContents(String directoryId) async {
    final data = await getMusicDirectory(directoryId);

    final directory = data['directory'] as Map<String, dynamic>?;
    if (directory == null) {
      return (folders: <Folder>[], tracks: <Track>[]);
    }

    final childList = directory['child'];
    if (childList == null) {
      return (folders: <Folder>[], tracks: <Track>[]);
    }

    final children = childList is List ? childList : [childList];
    final folders = <Folder>[];
    final tracks = <Track>[];
    final dirName = directory['name'] as String? ?? '';

    for (final child in children) {
      final item = child as Map<String, dynamic>;
      if (item['isDir'] == true) {
        folders.add(Folder.fromSubsonic(item, api: this));
      } else {
        tracks.add(Track.fromSubsonic(item, this, parentFolderName: dirName));
      }
    }

    return (folders: folders, tracks: tracks);
  }

  /// Get all tracks (songs) within a directory, recursively fetching subdirectories
  /// in parallel for efficiency.
  Future<List<Track>> getAllTracksInDirectory(String directoryId) async {
    final contents = await getDirectoryContents(directoryId);
    final tracks = <Track>[...contents.tracks];

    // Fetch subdirectories in parallel instead of sequentially
    if (contents.folders.isNotEmpty) {
      final subResults = await Future.wait(
        contents.folders
            .where((f) => f.id != null)
            .map((f) => getAllTracksInDirectory(f.id!)),
      );
      for (final subTracks in subResults) {
        tracks.addAll(subTracks);
      }
    }

    return tracks;
  }

  /// Get random songs from the library.
  /// Useful for showing tracks immediately without requiring a search query.
  Future<List<Track>> getRandomSongs({int size = 100}) async {
    try {
      final uri = _buildUri('getRandomSongs', {
        'size': size.toString(),
      });

      final response = await _get(uri);
      final data = _parseResponse(response);

      final randomSongs = data['randomSongs'] as Map<String, dynamic>?;
      if (randomSongs == null) return [];

      final songList = randomSongs['song'];
      if (songList == null) return [];

      final items = songList is List ? songList : [songList];
      return items
          .map((item) => Track.fromSubsonic(item as Map<String, dynamic>, this))
          .toList();
    } catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('Failed to get random songs: $e');
    }
  }

  /// Get a list of albums using getAlbumList2 (tag-based).
  /// [type] can be: 'newest', 'recent', 'frequent', 'random', 'alphabeticalByName', etc.
  Future<List<Folder>> getAlbumList2({
    required String type,
    int size = 20,
    int offset = 0,
  }) async {
    final cacheKey = 'albumList2_${type}_${size}_$offset';
    final cached = _getFromCache<List<Folder>>(cacheKey);
    if (cached != null) return cached;

    try {
      final uri = _buildUri('getAlbumList2', {
        'type': type,
        'size': size.toString(),
        'offset': offset.toString(),
      });

      final response = await _get(uri);
      final data = _parseResponse(response);

      final albumList = data['albumList2'] as Map<String, dynamic>?;
      if (albumList == null) return [];

      final albums = albumList['album'];
      if (albums == null) return [];

      final items = albums is List ? albums : [albums];
      final result = items
          .map((item) => Folder.fromSubsonic(item as Map<String, dynamic>, api: this))
          .toList();

      _putInCache(cacheKey, result);
      return result;
    } catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('Failed to get album list: $e');
    }
  }

  /// Search for songs, albums, and artists using search3.
  Future<({List<Track> songs, List<Folder> albums})> search3(
    String query, {
    int songCount = 50,
    int albumCount = 20,
    int artistCount = 20,
  }) async {
    try {
      final uri = _buildUri('search3', {
        'query': query,
        'songCount': songCount.toString(),
        'albumCount': albumCount.toString(),
        'artistCount': artistCount.toString(),
      });

      final response = await _get(uri);
      final data = _parseResponse(response);

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
          songs.add(Track.fromSubsonic(item as Map<String, dynamic>, this));
        }
      }

      // Parse albums as folders
      final albumList = searchResult['album'];
      final albums = <Folder>[];
      if (albumList != null) {
        final items = albumList is List ? albumList : [albumList];
        for (final item in items) {
          albums.add(Folder.fromSubsonic(item as Map<String, dynamic>, api: this));
        }
      }

      return (songs: songs, albums: albums);
    } catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('Search failed: $e');
    }
  }

  /// Authenticate with Navidrome's native REST API and get a JWT token.
  Future<String> _getNativeApiToken() async {
    final baseUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    final uri = Uri.parse('$baseUrl/auth/login');

    try {
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(_httpTimeout);

      if (response.statusCode != 200) {
        throw SubsonicApiException('Native API login failed: HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token == null) {
        throw SubsonicApiException('Native API login: no token in response');
      }
      return token;
    } on Exception catch (e) {
      if (e is SubsonicApiException) rethrow;
      throw SubsonicApiException('Native API login failed: $e');
    }
  }

  /// Fetch all songs from Navidrome's native REST API with real filesystem paths.
  /// The native API returns the actual `path` field from the database,
  /// which is the real filesystem path (unlike the Subsonic API which returns
  /// tag-based virtual paths).
  Future<List<Map<String, dynamic>>> getAllSongsNativeApi() async {
    final baseUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    final token = await _getNativeApiToken();
    final allSongs = <Map<String, dynamic>>[];
    const pageSize = 500;
    var offset = 0;

    while (true) {
      final uri = Uri.parse('$baseUrl/api/song?_start=$offset&_end=${offset + pageSize}&_order=ASC&_sort=path');
      try {
        final response = await _httpClient.get(uri, headers: {
          'x-nd-authorization': 'Bearer $token',
        }).timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) {
          throw SubsonicApiException('Native API error: HTTP ${response.statusCode}');
        }

        final List<dynamic> songs = jsonDecode(response.body);
        if (songs.isEmpty) break;

        for (final song in songs) {
          allSongs.add(song as Map<String, dynamic>);
        }

        debugPrint('SubsonicApi: Fetched ${songs.length} songs (offset=$offset, total so far=${allSongs.length})');

        if (songs.length < pageSize) break;
        offset += pageSize;
      } catch (e) {
        if (e is SubsonicApiException) rethrow;
        throw SubsonicApiException('Native API request failed: $e');
      }
    }

    return allSongs;
  }

  /// Dispose the HTTP client.
  void dispose() {
    _httpClient.close();
  }
}

/// Internal cache entry with timestamp for TTL-based expiration.
class _CacheEntry {
  final dynamic data;
  final DateTime timestamp;

  _CacheEntry({required this.data, required this.timestamp});
}
