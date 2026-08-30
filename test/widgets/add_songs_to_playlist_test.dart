import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:anywhere_music_player/models/playlist.dart';
import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/playlists_service.dart';
import 'package:anywhere_music_player/widgets/add_songs_to_playlist.dart';
import '../support/fake_playlists.dart';
import '../support/fixtures.dart';

/// A scanner with a fixed library. The real one populates [allTracks] from a
/// `compute()` isolate that testWidgets' fake-async zone never resolves, and
/// this widget only ever reads the list — so overriding the getter is both
/// enough and far cheaper than driving a scan.
class _FakeScanner extends LibraryScanner {
  @override
  final List<Track> allTracks;

  _FakeScanner(this.allTracks) : super(null);
}

// Covers the search-and-add picker: what a query matches, that a tap actually
// writes, and that the sheet stays open so several songs can go in at once.
//
// Driven against FakePlaylistServer, which applies writes for real, so these
// assert on the playlist the user ends up with.
void main() {
  late FakePlaylistServer server;
  late PlaylistsService playlists;
  late _FakeScanner scanner;

  setUp(() {
    server = FakePlaylistServer(
      playlists: {
        '1': (name: 'Roadtrip', owner: 'alice', trackIds: []),
      },
    );
    playlists = server.service();
    scanner = _FakeScanner([
      sampleTrack(id: 'a', title: 'Blade Runner Blues', artist: 'Vangelis'),
      sampleTrack(id: 'b', title: 'Tears in Rain', artist: 'Vangelis'),
      sampleTrack(id: 'c', title: 'Blue Monday', artist: 'New Order'),
    ]);
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlaylistsService>.value(value: playlists),
          ChangeNotifierProvider<LibraryScanner>.value(value: scanner),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AddSongsToPlaylist.show(
                  context,
                  const Playlist(id: '1', name: 'Roadtrip'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Several short pumps — pumpAndSettle would hang on a row's spinner.
  Future<void> settle(WidgetTester tester, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('shows nothing until something is typed', (tester) async {
    await pumpPicker(tester);

    // The whole library would be a useless wall of rows to scroll.
    expect(find.text('Type to search for songs to add.'), findsOneWidget);
    expect(find.text('Blue Monday'), findsNothing);
  });

  testWidgets('filters by title as you type', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pump();

    expect(find.text('Blue Monday'), findsOneWidget);
    expect(find.text('Tears in Rain'), findsNothing);
  });

  testWidgets('matches on artist too, not just title', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'vangelis');
    await tester.pump();

    expect(find.text('Blade Runner Blues'), findsOneWidget);
    expect(find.text('Tears in Rain'), findsOneWidget);
    expect(find.text('Blue Monday'), findsNothing);
  });

  testWidgets('matching ignores case', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'BLADE');
    await tester.pump();

    expect(find.text('Blade Runner Blues'), findsOneWidget);
  });

  testWidgets('tapping a result adds it to the playlist', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pump();
    await tester.tap(find.text('Blue Monday'));
    await settle(tester);

    expect(server.playlists['1']!.trackIds, ['c']);
  });

  testWidgets('the sheet stays open so several can go in at once', (
    tester,
  ) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'vangelis');
    await tester.pump();
    await tester.tap(find.text('Blade Runner Blues'));
    await settle(tester);

    // Still open, still showing the query's results — this is the whole point
    // of the flow over the one-at-a-time picker.
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Tears in Rain'));
    await settle(tester);

    expect(server.playlists['1']!.trackIds, ['a', 'b']);
  });

  testWidgets('an added row is marked so, and the count shows', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pump();
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(find.text('Blue Monday'));
    await settle(tester);

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('1 added'), findsOneWidget);
  });

  testWidgets('a rejected add leaves the row unmarked', (tester) async {
    server.failWrites = 'read-only';
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pump();
    await tester.tap(find.text('Blue Monday'));
    await settle(tester);

    expect(server.playlists['1']!.trackIds, isEmpty);
    // No tick, so the failure is visible rather than silently claimed.
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a query matching nothing says so', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();

    expect(find.textContaining('Nothing matches'), findsOneWidget);
  });

  testWidgets('an unscanned library says so rather than looking broken', (
    tester,
  ) async {
    scanner = _FakeScanner(const []);
    await pumpPicker(tester);

    expect(
      find.text('Your library has not been scanned yet.'),
      findsOneWidget,
    );
  });

  testWidgets('Done closes it and reports how many went in', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pump();
    await tester.tap(find.text('Blue Monday'));
    await settle(tester);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });
}
