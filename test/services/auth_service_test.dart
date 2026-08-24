import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

/// A secure-storage platform whose reads always throw, simulating a
/// flutter_secure_storage plugin failure (e.g. a corrupted keystore) rather
/// than the credentials themselves being wrong. Backed by [data] so writes
/// (login) and deletes (logout) still behave normally — only reads fail.
class _UnreadableSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> data;
  _UnreadableSecureStoragePlatform(this.data);

  @override
  Future<String?> read({required String key, required Map<String, String> options}) {
    throw Exception('plugin failure: keystore unavailable');
  }

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      data.containsKey(key);

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async =>
      data.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => data.clear();

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => data;

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async =>
      data[key] = value;
}

http.Response _pingOk() => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok'},
  }),
  200,
);

http.Response _pingRejected() => http.Response(
  jsonEncode({
    'subsonic-response': {
      'status': 'failed',
      'error': {'code': 40, 'message': 'Wrong username or password'},
    },
  }),
  200,
);

void main() {
  late Map<String, String> secureStore;

  setUp(() {
    secureStore = {};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(secureStore);
    SharedPreferences.setMockInitialValues({});
  });

  group('initialize (session restore)', () {
    test('stays logged out when no credentials are stored', () async {
      final auth = AuthService();
      await auth.initialize();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.currentUser, isNull);
    });

    test('restores the session when stored credentials still ping ok', () async {
      secureStore['server_url'] = 'https://navidrome.example.com';
      secureStore['username'] = 'alice';
      secureStore['password'] = 'secret';

      final auth = AuthService(
        apiFactory: ({required serverUrl, required username, required password}) =>
            SubsonicApiService(
              serverUrl: serverUrl,
              username: username,
              password: password,
              httpClient: MockClient((request) async => _pingOk()),
            ),
      );
      await auth.initialize();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.username, 'alice');
    });

    test('clears stored credentials when the server rejects them (code 40)', () async {
      secureStore['server_url'] = 'https://navidrome.example.com';
      secureStore['username'] = 'alice';
      secureStore['password'] = 'wrong';

      final auth = AuthService(
        apiFactory: ({required serverUrl, required username, required password}) =>
            SubsonicApiService(
              serverUrl: serverUrl,
              username: username,
              password: password,
              httpClient: MockClient((request) async => _pingRejected()),
            ),
      );
      await auth.initialize();

      expect(auth.isAuthenticated, isFalse);
      expect(secureStore.containsKey('server_url'), isFalse);
    });

    test('keeps the session on a transient ping failure (offline-first)', () async {
      // Documented behavior: only an explicit "wrong credentials" (code 40)
      // logs the user out. Anything else (offline, timeout, server down) must
      // not — see docs/decisions.md.
      secureStore['server_url'] = 'https://navidrome.example.com';
      secureStore['username'] = 'alice';
      secureStore['password'] = 'secret';

      final auth = AuthService(
        apiFactory: ({required serverUrl, required username, required password}) =>
            SubsonicApiService(
              serverUrl: serverUrl,
              username: username,
              password: password,
              httpClient: MockClient((request) async => http.Response('Server Error', 500)),
            ),
      );
      await auth.initialize();

      expect(auth.isAuthenticated, isTrue);
      expect(secureStore.containsKey('server_url'), isTrue);
    });

    test('a secure-storage read failure does not wipe stored credentials', () async {
      // Regression for J2: a flutter_secure_storage plugin failure on
      // startup must not be treated as "credentials rejected" — only a
      // code-40 ping response may clear storage. See docs/decisions.md.
      secureStore['server_url'] = 'https://navidrome.example.com';
      secureStore['username'] = 'alice';
      secureStore['password'] = 'secret';
      FlutterSecureStoragePlatform.instance = _UnreadableSecureStoragePlatform(secureStore);

      final auth = AuthService(
        apiFactory: ({required serverUrl, required username, required password}) =>
            SubsonicApiService(
              serverUrl: serverUrl,
              username: username,
              password: password,
              httpClient: MockClient((request) async => _pingOk()),
            ),
      );
      await auth.initialize();

      // Couldn't even read the credentials this launch, so no session — but
      // critically, they must still be there for the *next* launch to retry.
      expect(auth.isAuthenticated, isFalse);
      expect(secureStore.containsKey('server_url'), isTrue);
      expect(secureStore.containsKey('username'), isTrue);
      expect(secureStore.containsKey('password'), isTrue);
    });

    test('migrates legacy SharedPreferences credentials into secure storage', () async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://navidrome.example.com',
        'username': 'alice',
        'password': 'secret',
      });

      final auth = AuthService(
        apiFactory: ({required serverUrl, required username, required password}) =>
            SubsonicApiService(
              serverUrl: serverUrl,
              username: username,
              password: password,
              httpClient: MockClient((request) async => _pingOk()),
            ),
      );
      await auth.initialize();

      expect(auth.isAuthenticated, isTrue);
      expect(secureStore['username'], 'alice');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('username'), isNull); // removed after migration
    });
  });

  group('login', () {
    test('on success, persists credentials to secure storage and authenticates', () async {
      final auth = AuthService(
        apiFactory: ({required serverUrl, required username, required password}) =>
            SubsonicApiService(
              serverUrl: serverUrl,
              username: username,
              password: password,
              httpClient: MockClient((request) async => _pingOk()),
            ),
      );

      await auth.login('https://navidrome.example.com', 'alice', 'secret');

      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.username, 'alice');
      expect(secureStore['username'], 'alice');
      expect(secureStore['password'], 'secret');
    });

    test('on rejection, throws and does not authenticate or persist anything', () async {
      final auth = AuthService(
        apiFactory: ({required serverUrl, required username, required password}) =>
            SubsonicApiService(
              serverUrl: serverUrl,
              username: username,
              password: password,
              httpClient: MockClient((request) async => _pingRejected()),
            ),
      );

      await expectLater(
        () => auth.login('https://navidrome.example.com', 'alice', 'wrong'),
        throwsA(isA<SubsonicApiException>()),
      );

      expect(auth.isAuthenticated, isFalse);
      expect(secureStore.containsKey('username'), isFalse);
    });
  });

  group('logout', () {
    test('clears in-memory state and secure storage', () async {
      final auth = AuthService(
        apiFactory: ({required serverUrl, required username, required password}) =>
            SubsonicApiService(
              serverUrl: serverUrl,
              username: username,
              password: password,
              httpClient: MockClient((request) async => _pingOk()),
            ),
      );
      await auth.login('https://navidrome.example.com', 'alice', 'secret');

      await auth.logout();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.currentUser, isNull);
      expect(secureStore, isEmpty);
    });
  });
}
