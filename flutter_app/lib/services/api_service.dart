import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../models/folder.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class ApiService {
  final String baseUrl;
  String? _authToken;

  ApiService({required this.baseUrl});

  void setAuthToken(String token) {
    _authToken = token;
  }

  void clearAuthToken() {
    _authToken = null;
  }

  Map<String, String> getHeaders({bool authenticated = false}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (authenticated && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
      debugPrint('🔑 Using auth token: ${_authToken!.substring(0, 20)}...');
    } else if (authenticated && _authToken == null) {
      debugPrint('⚠️ AUTH REQUIRED but token is NULL!');
    }

    return headers;
  }

  /// Sign up a new user
  Future<AuthResponse> signup(
      String email, String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/signup'),
        headers: getHeaders(),
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AuthResponse.fromJson(data);
      } else {
        final error = jsonDecode(response.body);
        throw ApiException(
          error['detail'] ?? 'Signup failed',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Login an existing user
  Future<AuthResponse> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: getHeaders(),
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AuthResponse.fromJson(data);
      } else {
        final error = jsonDecode(response.body);
        throw ApiException(
          error['detail'] ?? 'Login failed',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Fetch all tracks
  Future<List<Track>> getTracks({String? folderPath, String? parentFolder, int? limit}) async {
    try {
      var uri = Uri.parse('$baseUrl/tracks');

      // Add query parameters for filtering
      final queryParams = <String, String>{};

      if (folderPath != null && folderPath.isNotEmpty) {
        queryParams['folder_path'] = folderPath;
      }

      if (parentFolder != null && parentFolder.isNotEmpty) {
        queryParams['parent_folder'] = parentFolder;
      }

      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }

      if (queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }

      debugPrint('🌐 API Request: $uri');

      final response = await http.get(
        uri,
        headers: getHeaders(authenticated: true),
      );

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Track.fromJson(json)).toList();
      } else {
        debugPrint('❌ Failed to fetch tracks. Status: ${response.statusCode}');
        debugPrint('❌ Response body: ${response.body}');

        String errorMessage = 'Failed to fetch tracks (${response.statusCode})';
        try {
          final error = jsonDecode(response.body);
          errorMessage = error['detail'] ?? errorMessage;
        } catch (_) {
          // Response body is not JSON, use the raw body
          if (response.body.isNotEmpty) {
            errorMessage = response.body;
          }
        }

        throw ApiException(errorMessage, response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Fetch root-level tracks (not in any folder)
  Future<List<Track>> getRootTracks() async {
    try {
      final uri = Uri.parse('$baseUrl/tracks/root-tracks');
      debugPrint('🌐 API Request: $uri');

      final response = await http.get(
        uri,
        headers: getHeaders(authenticated: true),
      );

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Track.fromJson(json)).toList();
      } else {
        debugPrint('❌ Failed to fetch root tracks. Status: ${response.statusCode}');
        debugPrint('❌ Response body: ${response.body}');

        String errorMessage = 'Failed to fetch root tracks (${response.statusCode})';
        try {
          final error = jsonDecode(response.body);
          errorMessage = error['detail'] ?? errorMessage;
        } catch (_) {
          // Response body is not JSON, use the raw body
          if (response.body.isNotEmpty) {
            errorMessage = response.body;
          }
        }

        throw ApiException(errorMessage, response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Get folders with hierarchical support
  /// - Without parentPath: Returns only root-level folders
  /// - With parentPath="Animes": Returns direct children like "Animes/Pokemon"
  Future<List<Folder>> getFolders({String? parentPath}) async {
    try {
      var uri = Uri.parse('$baseUrl/tracks/folders');

      // Add query parameters for hierarchical navigation
      if (parentPath != null && parentPath.isNotEmpty) {
        uri = uri.replace(queryParameters: {'parent_path': parentPath});
      }

      debugPrint('🌐 API Request: $uri');

      final response = await http.get(
        uri,
        headers: getHeaders(authenticated: true),
      );

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Folder.fromJson(json)).toList();
      } else {
        debugPrint('❌ Failed to fetch folders. Status: ${response.statusCode}');
        debugPrint('❌ Response body: ${response.body}');

        String errorMessage = 'Failed to fetch folders (${response.statusCode})';
        try {
          final error = jsonDecode(response.body);
          errorMessage = error['detail'] ?? errorMessage;
        } catch (_) {
          // Response body is not JSON, use the raw body
          if (response.body.isNotEmpty) {
            errorMessage = response.body;
          }
        }

        throw ApiException(errorMessage, response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Search folders by name
  Future<List<Folder>> searchFolders(String query) async {
    try {
      final uri = Uri.parse('$baseUrl/tracks/folders/search')
          .replace(queryParameters: {'query': query});

      final response = await http.get(
        uri,
        headers: getHeaders(authenticated: true),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Folder.fromJson(json)).toList();
      } else {
        throw ApiException(
          'Folder search failed',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Search tracks by title or folder path
  Future<List<Track>> searchTracks(String query) async {
    try {
      final uri = Uri.parse('$baseUrl/tracks/search').replace(queryParameters: {
        'query': query,
      });

      final response = await http.get(
        uri,
        headers: getHeaders(authenticated: true),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Track.fromJson(json)).toList();
      } else {
        throw ApiException(
          'Search failed',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }
}
