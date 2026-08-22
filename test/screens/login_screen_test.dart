import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:anywhere_music_player/screens/login_screen.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

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

Widget _wrap(AuthService auth) => ChangeNotifierProvider<AuthService>.value(
  value: auth,
  child: const MaterialApp(home: LoginScreen()),
);

void main() {
  setUp(() {
    dotenv.testLoad(mergeWith: {'API_BASE_URL': 'https://navidrome.example.com'});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  testWidgets('shows validation errors when submitting empty fields', (tester) async {
    await tester.pumpWidget(_wrap(AuthService()));

    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(find.text('Please enter your username'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('a successful login clears the form error and authenticates', (tester) async {
    final auth = AuthService(
      apiFactory: ({required serverUrl, required username, required password}) => SubsonicApiService(
        serverUrl: serverUrl,
        username: username,
        password: password,
        httpClient: MockClient((request) async => _pingOk()),
      ),
    );

    await tester.pumpWidget(_wrap(auth));

    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'alice');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(auth.isAuthenticated, isTrue);
    expect(find.text('Please enter your username'), findsNothing);
  });

  testWidgets('a rejected login shows the server error message', (tester) async {
    final auth = AuthService(
      apiFactory: ({required serverUrl, required username, required password}) => SubsonicApiService(
        serverUrl: serverUrl,
        username: username,
        password: password,
        httpClient: MockClient((request) async => _pingRejected()),
      ),
    );

    await tester.pumpWidget(_wrap(auth));

    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'alice');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(auth.isAuthenticated, isFalse);
    expect(find.text('Wrong username or password'), findsOneWidget);
  });

  testWidgets('the Connect button shows a spinner and is disabled while logging in', (tester) async {
    final gate = Completer<void>();
    final auth = AuthService(
      apiFactory: ({required serverUrl, required username, required password}) => SubsonicApiService(
        serverUrl: serverUrl,
        username: username,
        password: password,
        httpClient: MockClient((request) async {
          await gate.future;
          return _pingOk();
        }),
      ),
    );

    await tester.pumpWidget(_wrap(auth));
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'alice');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret');
    await tester.tap(find.text('Connect'));
    await tester.pump(); // start the async login, don't let it finish yet

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the password visibility toggle switches obscureText', (tester) async {
    await tester.pumpWidget(_wrap(AuthService()));

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();

    expect(find.byIcon(Icons.visibility), findsNothing);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });
}
