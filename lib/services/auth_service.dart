import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  /// Use flutter_secure_storage for credentials (encrypted on-device).
  /// Falls back to SharedPreferences for non-sensitive data (server URL).
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Test-only seam: lets tests substitute a SubsonicApiService backed by a
  // fake http.Client instead of one that hits the network. Production call
  // sites never pass this, so behavior is unchanged.
  final SubsonicApiService Function({
    required String serverUrl,
    required String username,
    required String password,
  }) _apiFactory;

  AuthService({
    @visibleForTesting
    SubsonicApiService Function({
      required String serverUrl,
      required String username,
      required String password,
    })?
    apiFactory,
  }) : _apiFactory = apiFactory ?? SubsonicApiService.new;

  SubsonicApiService? get apiService => _apiService;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _apiService != null && _currentUser != null;
  bool get isLoading => _isLoading;

  /// Initialize auth state from stored credentials.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Try reading from secure storage first
      String? serverUrl = await _secureStorage.read(key: _serverUrlKey);
      String? username = await _secureStorage.read(key: _usernameKey);
      String? password = await _secureStorage.read(key: _passwordKey);

      // Migrate from SharedPreferences if secure storage is empty
      if (serverUrl == null || username == null || password == null) {
        final migrated = await _migrateFromSharedPreferences();
        if (migrated) {
          serverUrl = await _secureStorage.read(key: _serverUrlKey);
          username = await _secureStorage.read(key: _usernameKey);
          password = await _secureStorage.read(key: _passwordKey);
        }
      }

      if (serverUrl != null && username != null && password != null) {
        final api = _apiFactory(
          serverUrl: serverUrl,
          username: username,
          password: password,
        );

        // Verify credentials are still valid. Only clear stored credentials
        // when the server actively rejects them (Subsonic error code 40 =
        // wrong username/password); any other failure (offline, timeout,
        // server down) is transient and must not log the user out — the
        // library cache already supports fully offline browsing, so we keep
        // the session and let the user retry once connectivity returns.
        try {
          await api.ping();
          _apiService = api;
          _currentUser = User(username: username);
          if (kDebugMode) debugPrint('AuthService: Restored session for $username');
        } on SubsonicApiException catch (e) {
          if (e.code == 40) {
            debugPrint('AuthService: Stored credentials rejected by server, clearing');
            await _clearStorage();
          } else {
            debugPrint('AuthService: Ping failed ($e), continuing offline with cached session');
            _apiService = api;
            _currentUser = User(username: username);
          }
        } catch (e) {
          debugPrint('AuthService: Ping failed ($e), continuing offline with cached session');
          _apiService = api;
          _currentUser = User(username: username);
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
      final api = _apiFactory(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );

      // Verify credentials by pinging the server
      await api.ping();

      // Save credentials to secure storage
      await _secureStorage.write(key: _serverUrlKey, value: serverUrl);
      await _secureStorage.write(key: _usernameKey, value: username);
      await _secureStorage.write(key: _passwordKey, value: password);

      _apiService = api;
      _currentUser = User(username: username);
      if (kDebugMode) debugPrint('AuthService: Logged in as $username');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout the current user.
  Future<void> logout() async {
    _apiService?.dispose();
    await _clearStorage();
    _apiService = null;
    _currentUser = null;
    notifyListeners();
  }

  /// Clear all stored authentication data.
  Future<void> _clearStorage() async {
    try {
      await _secureStorage.delete(key: _serverUrlKey);
      await _secureStorage.delete(key: _usernameKey);
      await _secureStorage.delete(key: _passwordKey);
    } catch (e) {
      debugPrint('Error clearing secure storage: $e');
    }
    // Also clear legacy SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_serverUrlKey);
      await prefs.remove(_usernameKey);
      await prefs.remove(_passwordKey);
    } catch (_) {}
  }

  /// Migrate credentials from SharedPreferences to secure storage.
  /// Returns true if migration occurred.
  Future<bool> _migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString(_serverUrlKey);
      final username = prefs.getString(_usernameKey);
      final password = prefs.getString(_passwordKey);

      if (serverUrl != null && username != null && password != null) {
        await _secureStorage.write(key: _serverUrlKey, value: serverUrl);
        await _secureStorage.write(key: _usernameKey, value: username);
        await _secureStorage.write(key: _passwordKey, value: password);

        // Remove from SharedPreferences after successful migration
        await prefs.remove(_serverUrlKey);
        await prefs.remove(_usernameKey);
        await prefs.remove(_passwordKey);

        debugPrint('AuthService: Migrated credentials to secure storage');
        return true;
      }
    } catch (e) {
      debugPrint('AuthService: Migration from SharedPreferences failed: $e');
    }
    return false;
  }
}
