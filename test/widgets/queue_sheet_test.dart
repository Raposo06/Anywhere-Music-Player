import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/widgets/queue_sheet.dart';
import '../support/fixtures.dart';

Widget _wrap(AudioPlayerService service) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AudioPlayerService>.value(value: service),
      // No cover art on any fixture in this file, so an unauthenticated
      // (apiService == null) AuthService resolves the same as a real one.
      ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
    ],
    child: const MaterialApp(home: Scaffold(body: QueueSheet())),
  );
}

void main() {
  testWidgets('shows an empty state with nothing playing and nothing queued', (tester) async {
    final service = AudioPlayerService();

    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    expect(find.text('Queue is empty'), findsOneWidget);
  });

  testWidgets('shows the current track under Now Playing', (tester) async {
    final service = AudioPlayerService()..seedForTest(currentTrack: sampleTrack(title: 'Playing Now'));

    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Playing Now'), findsOneWidget);
    expect(find.byIcon(Icons.equalizer), findsOneWidget); // highlight marker, not a drag handle
  });

  testWidgets('lists manual queue additions under Next in Queue', (tester) async {
    final service = AudioPlayerService()
      ..seedForTest(
        currentTrack: sampleTrack(id: '0', title: 'Playing Now'),
        queue: [sampleTrack(id: '1', title: 'Queued One'), sampleTrack(id: '2', title: 'Queued Two')],
      );

    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    expect(find.text('Next in Queue'), findsOneWidget);
    expect(find.text('Queued One'), findsOneWidget);
    expect(find.text('Queued Two'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
  });

  testWidgets('lists upcoming playlist tracks under Next from playlist', (tester) async {
    final service = AudioPlayerService()
      ..seedForTest(
        currentTrack: sampleTrack(id: '1', title: 'Track One'),
        playlist: [
          sampleTrack(id: '1', title: 'Track One'),
          sampleTrack(id: '2', title: 'Track Two'),
          sampleTrack(id: '3', title: 'Track Three'),
        ],
        currentIndex: 0,
      );

    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    expect(find.text('Next from playlist'), findsOneWidget);
    expect(find.text('Track Two'), findsOneWidget);
    expect(find.text('Track Three'), findsOneWidget);
  });

  testWidgets('swiping a manual queue row away removes it from the queue', (tester) async {
    final service = AudioPlayerService()
      ..seedForTest(
        currentTrack: sampleTrack(id: '0', title: 'Playing Now'),
        queue: [sampleTrack(id: '1', title: 'Queued One'), sampleTrack(id: '2', title: 'Queued Two')],
      );

    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    await tester.drag(find.text('Queued One'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(service.queue.map((t) => t.title), ['Queued Two']);
    expect(find.text('Queued One'), findsNothing);
  });

  testWidgets('the close button dismisses the sheet', (tester) async {
    final service = AudioPlayerService()..seedForTest(currentTrack: sampleTrack());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AudioPlayerService>.value(value: service),
          ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => QueueSheet.show(context),
                child: const Text('Open Queue'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Queue'));
    await tester.pumpAndSettle();
    expect(find.byType(QueueSheet), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(QueueSheet), findsNothing);
  });
}
