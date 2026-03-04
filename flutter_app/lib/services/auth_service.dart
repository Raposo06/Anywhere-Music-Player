import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'subsonic_api_service.dart';

class AuthService with ChangeNotifier {
  SubsonicApiService? _apiService;
  User? _currentUser;
  bool _isLoading = false;

  static const String _serverUrlKey = 'server_url';
  static const String _usernameKey = 'username';
  static const String _passwordKey = 'password';

  SubsonicApiService? get apiService => _apiService;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _apiService != null && _currentUser != null;
  bool get isLoading => _isLoading;

  /// Initialize auth state from stored credentials.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString(_serverUrlKey);
      final username = prefs.getString(_usernameKey);
      final password = prefs.getString(_passwordKey);

      if (serverUrl != null && username != null && password != null) {
        final api = SubsonicApiService(
          serverUrl: serverUrl,
          username: username,
          password: password,
        );

        // Verify credentials are still valid
        try {
          await api.ping();
          _apiService = api;
          _currentUser = User(username: username);
          debugPrint('AuthService: Restored session for $username @ $serverUrl');
        } catch (e) {
          debugPrint('AuthService: Stored credentials invalid, clearing');
          await _clearStorage();
        }
      }
    } catch (e) {
      debugPrint('Error initializing auth: $e');
      await _clearStorage();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login to a Navidrome server using Subsonic API credentials.
  Future<void> login(String serverUrl, String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final api = SubsonicApiService(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );

      // Verify credentials by pinging the server
      await api.ping();

      // Save credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverUrlKey, serverUrl);
      await prefs.setString(_usernameKey, username);
      await prefs.setString(_passwordKey, password);

      _apiService = api;
      _currentUser = User(username: username);
      debugPrint('AuthService: Logged in as $username @ $serverUrl');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout the current user.
  Future<void> logout() async {
    await _clearStorage();
    _apiService = null;
    _currentUser = null;
    notifyListeners();
  }

  /// Clear all stored authentication data.
  Future<void> _clearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_passwordKey);
  }
}
