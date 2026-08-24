import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/widgets/track_tile.dart';
import '../support/fixtures.dart';

// TrackTile replaces three near-identical private tiles (home, all-tracks,
// folder-detail) that had already drifted apart — home was missing
// swipe-to-queue. Previously untestable directly: private classes inside
// screen files, reachable only through a full screen pump. See
// docs/reviews/2026-08-22-architecture-review.html Candidate 04.
void main() {
  Widget wrap(AudioPlayerService player, Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AudioPlayerService>.value(value: player),
        // No cover art on any fixture in this file, so an unauthenticated
        // (apiService == null) AuthService resolves the same as a real one.
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('shows the equalizer marker only for the current track', (tester) async {
    final track = sampleTrack(id: '1', title: 'Playing Now');
    final player = AudioPlayerService()..seedForTest(currentTrack: track);

    await tester.pumpWidget(wrap(player, TrackTile(track: track, onTap: () {})));
    await tester.pump();

    expect(find.byIcon(Icons.equalizer), findsOneWidget);
  });

  testWidgets('no equalizer marker when this tile is not the current track', (tester) async {
    final player = AudioPlayerService()
      ..seedForTest(currentTrack: sampleTrack(id: 'other', title: 'Something Else'));

    await tester.pumpWidget(wrap(
      player,
      TrackTile(track: sampleTrack(id: '1', title: 'Not Playing'), onTap: () {}),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.equalizer), findsNothing);
  });

  testWidgets('tapping the tile calls onTap', (tester) async {
    final player = AudioPlayerService();
    var tapped = false;

    await tester.pumpWidget(wrap(
      player,
      TrackTile(track: sampleTrack(title: 'Tap Me'), onTap: () => tapped = true),
    ));
    await tester.pump();
    await tester.tap(find.text('Tap Me'));

    expect(tapped, isTrue);
  });

  testWidgets('leadingIndex renders a 1-based row number; null omits it', (tester) async {
    final player = AudioPlayerService();

    await tester.pumpWidget(wrap(
      player,
      TrackTile(track: sampleTrack(), onTap: () {}, leadingIndex: 4),
    ));
    await tester.pump();
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(wrap(
      player,
      TrackTile(track: sampleTrack(), onTap: () {}),
    ));
    await tester.pump();
    expect(find.text('5'), findsNothing);
  });

  testWidgets('swipe enqueues the track and shows the snackbar (swipeToQueue defaults on)', (tester) async {
    // A track must already be playing, or addToQueue() falls through to
    // playTrack() — which needs a live platform audio backend this test
    // doesn't have. See AudioPlayerService.addToQueue.
    final player = AudioPlayerService()
      ..seedForTest(currentTrack: sampleTrack(id: '0', title: 'Already Playing'));
    final track = sampleTrack(id: '1', title: 'Swipe Me');

    await tester.pumpWidget(wrap(player, TrackTile(track: track, onTap: () {})));
    await tester.pump();

    await tester.drag(find.text('Swipe Me'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(player.queue.map((t) => t.title), ['Swipe Me']);
    expect(find.text('Added to queue: Swipe Me'), findsOneWidget);
  });

  testWidgets('swipeToQueue: false renders a plain tile with no dismiss gesture', (tester) async {
    final player = AudioPlayerService()
      ..seedForTest(currentTrack: sampleTrack(id: '0', title: 'Already Playing'));
    final track = sampleTrack(id: '1', title: 'No Swipe');

    await tester.pumpWidget(wrap(
      player,
      TrackTile(track: track, onTap: () {}, swipeToQueue: false),
    ));
    await tester.pump();

    expect(find.byType(Dismissible), findsNothing);

    await tester.drag(find.text('No Swipe'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(player.queue, isEmpty);
  });
}
