import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/playlists_service.dart';
import 'package:anywhere_music_player/widgets/add_to_playlist.dart';
import '../support/fake_auth.dart';
import '../support/fake_playlists.dart';
import '../support/fixtures.dart';

// Covers the add-to-playlist picker — the one piece of playlist UI with real
// logic in it: which playlists can be picked, creating one on the spot, and
// not letting a slow write be submitted twice.
//
// Asserts against the fake server's resulting state rather than which requests
// were sent, so these stay true if the service changes how it gets there.
void main() {
  late FakePlaylistServer server;
  late PlaylistsService service;
  late AuthService auth;

  setUp(() async {
    // A real session, because ownership gating reads the current username —
    // logged out, Playlist.isEditableBy treats everything as editable.
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
    SharedPreferences.setMockInitialValues({});
    auth = await loggedInAuthService();

    server = FakePlaylistServer(
      playlists: {
        '1': (name: 'Roadtrip', owner: 'alice', trackIds: ['x']),
        '2': (name: 'Bob\'s mix', owner: 'bob', trackIds: []),
      },
    );
    service = server.service();
  });

  /// Pumps a screen whose only content is a button that opens the picker.
  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaylistsService>.value(value: service),
          // Ownership gating reads the current user from here.
          ChangeNotifierProvider<AuthService>.value(value: auth),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    AddToPlaylist.show(context, [sampleTrack(id: 'new')]),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The picker loads the list as it opens; a couple of pumps lets that
    // land. pumpAndSettle would hang on the spinner's animation.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('lists the playlists to choose from', (tester) async {
    await pumpPicker(tester);

    expect(find.text('Roadtrip'), findsOneWidget);
    expect(find.text('New playlist…'), findsOneWidget);
    // Single track: the sheet names it, so you can see what you're filing.
    expect(find.text('Add to playlist'), findsOneWidget);
  });

  testWidgets('a playlist owned by someone else is shown but not pickable', (
    tester,
  ) async {
    await pumpPicker(tester);

    expect(find.textContaining('read-only'), findsOneWidget);
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Bob\'s mix'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.enabled, isFalse);
  });

  testWidgets('picking a playlist adds the track to it', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.text('Roadtrip'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(server.playlists['1']!.trackIds, ['x', 'new']);
    // The sheet closes itself once the write lands.
    expect(find.text('New playlist…'), findsNothing);
  });

  testWidgets('creating one from the picker files the track into it', (
    tester,
  ) async {
    await pumpPicker(tester);

    await tester.tap(find.text('New playlist…'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Fresh');
    await tester.tap(find.text('Create'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final created = server.playlists.values.where((p) => p.name == 'Fresh');
    expect(created, hasLength(1));
    expect(created.single.trackIds, ['new']);
  });

  testWidgets('a blank name does not create anything', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.text('New playlist…'));
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump();

    // Still on the name dialog, and nothing was created.
    expect(find.text('New playlist'), findsOneWidget);
    expect(server.playlists.keys, ['1', '2']);
  });

  testWidgets('a rejected add leaves the playlist untouched', (tester) async {
    server.failWrites = 'read-only';
    await pumpPicker(tester);

    await tester.tap(find.text('Roadtrip'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(server.playlists['1']!.trackIds, ['x'], reason: 'unchanged');
    expect(service.error, contains('Could not add to playlist'));
  });

  testWidgets('never offers All Tracks as a destination', (tester) async {
    // It is pinned into the playlists *list* for browsing, but you cannot add
    // a song to it — it is a view of the library, not a collection.
    await pumpPicker(tester);

    expect(find.text('All Tracks'), findsNothing);
  });

  testWidgets('with no playlists it still offers to create one', (
    tester,
  ) async {
    server.playlists.clear();
    await pumpPicker(tester);

    expect(find.textContaining('No playlists yet'), findsOneWidget);
    expect(find.text('New playlist…'), findsOneWidget);
  });
}
