import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/widgets/scrub_bar.dart';

// ScrubBar owns the drag/seek state machine the phone, desktop and TV player
// bars each used to write out in full — including the subtle rule that a seek
// is discarded when the track auto-advances mid-drag. None of the three copies
// was ever tested; this exercises the machine directly, with no player and no
// pumped screen. See docs/reviews Candidate 02.
void main() {
  late StreamController<Duration> position;
  late List<Duration> seeks;
  late ValueNotifier<String?> trackId;
  late ScrubBarView view;

  setUp(() {
    position = StreamController<Duration>.broadcast();
    seeks = [];
    trackId = ValueNotifier<String?>('a');
  });

  tearDown(() {
    position.close();
    trackId.dispose();
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    Duration duration = const Duration(seconds: 100),
    bool readOnly = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<String?>(
            valueListenable: trackId,
            builder: (_, id, _) => ScrubBar(
              duration: duration,
              trackId: id,
              position: position.stream,
              onSeek: readOnly ? null : seeks.add,
              builder: (_, v) {
                view = v;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('fraction and position track the stream when not dragging', (
    tester,
  ) async {
    await pumpBar(tester);
    position.add(const Duration(seconds: 25));
    await tester.pump();

    expect(view.fraction, 0.25);
    expect(view.position, const Duration(seconds: 25));
  });

  testWidgets('while dragging, the bar follows the drag, not the stream', (
    tester,
  ) async {
    await pumpBar(tester);
    position.add(const Duration(seconds: 10));
    await tester.pump();

    view.onChangeStart!(0.1);
    await tester.pump();
    view.onChanged!(0.8);
    await tester.pump();

    // Stream keeps ticking underneath — the bar ignores it mid-drag.
    position.add(const Duration(seconds: 12));
    await tester.pump();

    expect(view.fraction, 0.8);
    expect(view.position, const Duration(seconds: 80));
  });

  testWidgets('releasing a drag seeks to the drag target', (tester) async {
    await pumpBar(tester);

    view.onChangeStart!(0.0);
    await tester.pump();
    view.onChangeEnd!(0.42);
    await tester.pump();

    expect(seeks, [const Duration(seconds: 42)]);
  });

  testWidgets('a seek is discarded when the track advances mid-drag', (
    tester,
  ) async {
    await pumpBar(tester);

    view.onChangeStart!(0.0);
    await tester.pump();

    // Track auto-advances while the thumb is held.
    trackId.value = 'b';
    await tester.pump();

    view.onChangeEnd!(0.9);
    await tester.pump();

    expect(seeks, isEmpty);
  });

  testWidgets('a null onSeek makes the bar read-only', (tester) async {
    await pumpBar(tester, readOnly: true);
    position.add(const Duration(seconds: 50));
    await tester.pump();

    expect(view.fraction, 0.5);
    expect(view.onChangeStart, isNull);
    expect(view.onChanged, isNull);
    expect(view.onChangeEnd, isNull);
  });

  testWidgets('an unknown duration disables seeking and pins the bar', (
    tester,
  ) async {
    await pumpBar(tester, duration: Duration.zero);
    position.add(const Duration(seconds: 5));
    await tester.pump();

    expect(view.fraction, 0.0);
    expect(view.onChangeStart, isNull);
    expect(view.onChangeEnd, isNull);
  });

  group('formatPlaybackDuration', () {
    test('pads minutes and seconds under an hour', () {
      expect(formatPlaybackDuration(const Duration(minutes: 3, seconds: 5)),
          '03:05');
    });

    test('rolls over to h:mm:ss past an hour', () {
      expect(
        formatPlaybackDuration(const Duration(hours: 1, minutes: 10)),
        '1:10:00',
      );
    });

    test('null reads as zero', () {
      expect(formatPlaybackDuration(null), '00:00');
    });
  });
}
