// App-level smoke test. Replaces the default Flutter counter-app scaffold,
// which tested a widget ('0' / '+') that doesn't exist in this app and had
// never actually passed — see docs/operations.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:anywhere_music_player/main.dart';
import 'package:anywhere_music_player/screens/login_screen.dart';

void main() {
  setUp(() {
    // No stored credentials anywhere → AuthService.initialize() should land
    // on the logged-out state without making any real platform/network call.
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  testWidgets('with no stored credentials, the app boots to the login screen', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Anywhere Music Player'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
  });
}
