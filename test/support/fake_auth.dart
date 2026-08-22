import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

/// An [AuthService] already logged in as [username], backed by a fake
/// Subsonic server that always accepts the ping. Requires secure storage /
/// SharedPreferences to already be faked (see fake_path_provider.dart's
/// sibling pattern) — call this after setting those up in a test's setUp.
Future<AuthService> loggedInAuthService({String username = 'alice'}) async {
  final auth = AuthService(
    apiFactory: ({required serverUrl, required username, required password}) => SubsonicApiService(
      serverUrl: serverUrl,
      username: username,
      password: password,
      httpClient: MockClient((request) async => http.Response(
        jsonEncode({
          'subsonic-response': {'status': 'ok'},
        }),
        200,
      )),
    ),
  );
  await auth.login('https://navidrome.example.com', username, 'secret');
  return auth;
}
