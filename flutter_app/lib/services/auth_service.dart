import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthService with ChangeNotifier {
  final ApiService _apiService;
  User? _currentUser;
  String? _token;
  bool _isLoading = false;

  static const String _tokenKey = 'jwt_token';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _userUsernameKey = 'user_username';

  AuthService(this._apiService);

  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _currentUser != null;
  bool get isLoading => _isLoading;

  /// Initialize auth state from stored credentials
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    debugPrint('🔐 AuthService: Initializing...');

    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);

      if (_token != null) {
        debugPrint('🔐 AuthService: Found stored token: ${_token!.substring(0, 20)}...');
        // Restore user from stored data
        final userId = prefs.getString(_userIdKey);
        final email = prefs.getString(_userEmailKey);
        final username = prefs.getString(_userUsernameKey);

        if (userId != null && email != null && username != null) {
          _currentUser = User(
            id: userId,
            email: email,
            username: username,
            createdAt: DateTime.now(), // We don't store this
          );
          _apiService.setAuthToken(_token!);
          debugPrint('🔐 AuthService: Token set for user: $email');
        } else {
          // Token exists but user data is incomplete, clear everything
          debugPrint('⚠️ AuthService: Token found but user data incomplete, clearing');
          await _clearStorage();
        }
      } else {
        debugPrint('⚠️ AuthService: No stored token found');
      }
    } catch (e) {
      debugPrint('❌ Error initializing auth: $e');
      await _clearStorage();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign up a new user
  Future<void> signup(String email, String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.signup(email, username, password);
      await _saveAuthData(response.token, response.user);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login an existing user
  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.login(email, password);
      await _saveAuthData(response.token, response.user);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout the current user
  Future<void> logout() async {
    await _clearStorage();
    _currentUser = null;
    _token = null;
    _apiService.clearAuthToken();
    notifyListeners();
  }

  /// Save authentication data to storage
  Future<void> _saveAuthData(String token, User user) async {
    debugPrint('🔐 AuthService: Saving auth data for user: ${user.email}');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, user.id);
    await prefs.setString(_userEmailKey, user.email);
    await prefs.setString(_userUsernameKey, user.username);

    _token = token;
    _currentUser = user;
    _apiService.setAuthToken(token);
    debugPrint('🔐 AuthService: Token saved and set: ${token.substring(0, 20)}...');
  }

  /// Clear all stored authentication data
  Future<void> _clearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userUsernameKey);
  }
}
