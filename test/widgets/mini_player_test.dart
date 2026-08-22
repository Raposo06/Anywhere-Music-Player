import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/widgets/mini_player.dart';
import 'package:anywhere_music_player/screens/player_screen.dart';
import '../support/fixtures.dart';

Widget _wrap(AudioPlayerService service, {Widget child = const MiniPlayer()}) {
  return ChangeNotifierProvider<AudioPlayerService>.value(
    value: service,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('renders nothing when there is no current track', (tester) async {
    final service = AudioPlayerService();

    await tester.pumpWidget(_wrap(service));

    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text('Sample Track'), findsNothing);
    // The bar collapses to nothing rather than showing an empty shell.
    expect(tester.getSize(find.byType(MiniPlayer)).height, 0);
  });

  testWidgets('shows the current track title and playback controls', (tester) async {
    final service = AudioPlayerService()..seedForTest(currentTrack: sampleTrack(title: 'Now Playing Song'));

    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    expect(find.text('Now Playing Song'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    // Not playing (no live player attached) → shows the play icon.
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
  });

  testWidgets('tapping the bar opens the full player screen', (tester) async {
    final service = AudioPlayerService()..seedForTest(currentTrack: sampleTrack());

    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerScreen), findsOneWidget);
  });

  testWidgets('updates when the current track changes without rebuilding the parent', (tester) async {
    final service = AudioPlayerService()..seedForTest(currentTrack: sampleTrack(title: 'First Song'));

    await tester.pumpWidget(_wrap(service));
    await tester.pump();
    expect(find.text('First Song'), findsOneWidget);

    service.seedForTest(currentTrack: sampleTrack(id: '2', title: 'Second Song'));
    await tester.pump();

    expect(find.text('First Song'), findsNothing);
    expect(find.text('Second Song'), findsOneWidget);
  });
}
