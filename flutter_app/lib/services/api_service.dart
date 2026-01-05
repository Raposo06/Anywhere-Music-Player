import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/user.dart';

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

  Map<String, String> _getHeaders({bool authenticated = false}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (authenticated && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    return headers;
  }

  /// Sign up a new user
  Future<AuthResponse> signup(
      String email, String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/signup'),
        headers: _getHeaders(),
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
        headers: _getHeaders(),
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
  Future<List<Track>> getTracks({String? folderPath}) async {
    try {
      var uri = Uri.parse('$baseUrl/tracks');

      // Add query parameters for filtering
      final queryParams = <String, String>{};

      if (folderPath != null && folderPath.isNotEmpty) {
        queryParams['folder_path'] = folderPath;
      }

      if (queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }

      final response = await http.get(
        uri,
        headers: _getHeaders(authenticated: true),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Track.fromJson(json)).toList();
      } else {
        throw ApiException(
          'Failed to fetch tracks',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: $e');
    }
  }

  /// Get unique folder paths for grouping
  Future<List<String>> getFolders() async {
    try {
      final uri = Uri.parse('$baseUrl/tracks/folders');

      final response = await http.get(
        uri,
        headers: _getHeaders(authenticated: true),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final folders = data
            .map((item) => item['folder_path'] as String?)
            .whereType<String>()
            .toList();
        return folders;
      } else {
        throw ApiException(
          'Failed to fetch folders',
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
        headers: _getHeaders(authenticated: true),
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
