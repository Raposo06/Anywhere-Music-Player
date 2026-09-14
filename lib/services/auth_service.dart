import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'playback_reporter.dart';
import 'stream_url_resolver.dart';
import 'subsonic_api_service.dart';

/// The current session: who is logged in and the [SubsonicApiService] that
/// talks for them. A whole new client each login; disposed on logout.
///
/// Also the session-following [StreamUrlResolver] and [PlaybackReporter]
/// the player is built with. The player is constructed once, before login,
/// and must keep resolving against whatever session is current across
/// logout and re-login — so it holds *this* rather than a client, and each
/// call is delegated to the client of the moment. Until 2026-09-14 that was
/// two `Rotating*` wrappers re-pointed by listeners in `main.dart`; see
/// docs/decisions.md.
class AuthService
    with ChangeNotifier
    implements StreamUrlResolver, PlaybackReporter {
  SubsonicApiService? _apiService;
  User? _currentUser;
  bool _isLoading = false;

  static const String _serverUrlKey = 'server_url';
  static const String _usernameKey = 'username';
  static const String _passwordKey = 'password';

  /// Use flutter_secure_storage for credentials (encrypted on-device).
  /// Falls back to SharedPreferences for non-sensitive data (server URL).
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Test-only seam: lets tests substitute a SubsonicApiService backed by a
  // fake http.Client instead of one that hits the network. Production call
  // sites never pass this, so behavior is unchanged.
  final SubsonicApiService Function({
    required String serverUrl,
    required String username,
    required String password,
  })
  _apiFactory;

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

  // -------- The current session as resolver and reporter --------

  /// A URL needs a session; asking for one logged out is a programming
  /// error, not a state to paper over — same contract as [NoResolver].
  SubsonicApiService get _sessionOrThrow =>
      _apiService ?? (throw StateError('No session — not logged in?'));

  @override
  String buildStreamUrl(String songId) =>
      _sessionOrThrow.buildStreamUrl(songId);

  @override
  String buildCoverArtUrl(String coverArtId, {int? size}) =>
      _sessionOrThrow.buildCoverArtUrl(coverArtId, size: size);

  /// Reports while logged out are dropped, not thrown: "no session" is a
  /// normal state for telemetry to be in — same contract as
  /// [NoPlaybackReporter].
  @override
  Future<void> nowPlaying(String songId) async =>
      _apiService?.nowPlaying(songId);

  @override
  Future<void> scrobble(String songId, {DateTime? startedAt}) async =>
      _apiService?.scrobble(songId, startedAt: startedAt);

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
          if (kDebugMode)
            debugPrint('AuthService: Restored session for $username');
        } on SubsonicApiException catch (e) {
          if (e.code == 40) {
            debugPrint(
              'AuthService: Stored credentials rejected by server, clearing',
            );
            await _clearStorage();
          } else {
            debugPrint(
              'AuthService: Ping failed ($e), continuing offline with cached session',
            );
            _apiService = api;
            _currentUser = User(username: username);
          }
        } catch (e) {
          debugPrint(
            'AuthService: Ping failed ($e), continuing offline with cached session',
          );
          _apiService = api;
          _currentUser = User(username: username);
        }
      }
    } catch (e) {
      // This is a *read* failure (e.g. a flutter_secure_storage plugin
      // error), not a credentials-rejected response — must not clear
      // storage. Only the code-40 branch above may do that. Leave the
      // stored credentials alone so the next launch can retry the read;
      // this launch just starts logged out. See docs/decisions.md.
      debugPrint('Error initializing auth: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login to a Subsonic-compatible server (Gonic) using its credentials.
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
