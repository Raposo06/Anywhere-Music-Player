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
    return '$baseUrl/rest/stream?id=$songId&${_authQueryString()}';
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
  /// Uses getIndexes to get the artist/folder listing, then returns them as Folders.
  Future<List<Folder>> getFolders({String? musicFolderId}) async {
    final data = await getIndexes(musicFolderId: musicFolderId);

    final indexes = data['indexes'] as Map<String, dynamic>?;
    if (indexes == null) return [];

    final folders = <Folder>[];

    // Each index entry has a 'name' (letter) and 'artist' list
    final indexList = indexes['index'];
    if (indexList == null) return [];

    final items = indexList is List ? indexList : [indexList];
    for (final index in items) {
      final artistList = index['artist'];
      if (artistList == null) continue;

      final artists = artistList is List ? artistList : [artistList];
      for (final artist in artists) {
        folders.add(Folder.fromSubsonic(artist as Map<String, dynamic>, api: this));
      }
    }

    return folders;
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

    for (final child in children) {
      final item = child as Map<String, dynamic>;
      if (item['isDir'] == true) {
        folders.add(Folder.fromSubsonic(item, api: this));
      } else {
        tracks.add(Track.fromSubsonic(item, this));
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
