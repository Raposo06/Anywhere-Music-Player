import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/theme/app_theme.dart';
import 'package:anywhere_music_player/widgets/desktop/desktop_primitives.dart';
import 'package:anywhere_music_player/widgets/desktop/window_chrome.dart';

// Every clickable thing shows the hand cursor.
//
// This is not paranoia about a setting nobody would touch. Material's own
// default is `WidgetStateMouseCursor.adaptiveClickable`, which resolves to
// `kIsWeb ? click : basic` — so on desktop a button shows the plain *arrow*
// unless the app opts in, and it does so silently: nothing throws, nothing
// logs, the button still works. The opt-in lives in `buildAppTheme`'s button
// themes (see [pointerCursor]); these tests are what would catch its removal,
// or a Flutter upgrade changing the default back.
//
// Rows are covered too as the control: `HoverRow` sets the cursor directly
// rather than through a button theme, so a failure there means something much
// more basic broke.
void main() {
  /// The cursor the framework actually resolves under a pointer parked over
  /// [target] — the same path a real mouse takes, not a read of the widget's
  /// declared property.
  Future<MouseCursor?> cursorOver(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
    return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('a row', (tester) async {
    await pump(tester, HoverRow(onTap: () {}, child: const Text('row')));

    expect(
      await cursorOver(tester, find.text('row')),
      SystemMouseCursors.click,
    );
  });

  testWidgets('a filled pill — "Play All"', (tester) async {
    await pump(
      tester,
      ElevatedButton(onPressed: () {}, child: const Text('Play All')),
    );

    expect(
      await cursorOver(tester, find.text('Play All')),
      SystemMouseCursors.click,
    );
  });

  testWidgets('an outline pill — "Shuffle"', (tester) async {
    await pump(
      tester,
      OutlinedButton(onPressed: () {}, child: const Text('Shuffle')),
    );

    expect(
      await cursorOver(tester, find.text('Shuffle')),
      SystemMouseCursors.click,
    );
  });

  testWidgets('a filled button — "Add songs"', (tester) async {
    await pump(
      tester,
      FilledButton(onPressed: () {}, child: const Text('Add songs')),
    );

    expect(
      await cursorOver(tester, find.text('Add songs')),
      SystemMouseCursors.click,
    );
  });

  testWidgets('a text button', (tester) async {
    await pump(
      tester,
      TextButton(onPressed: () {}, child: const Text('Cancel')),
    );

    expect(
      await cursorOver(tester, find.text('Cancel')),
      SystemMouseCursors.click,
    );
  });

  testWidgets('the round play button', (tester) async {
    await pump(
      tester,
      AccentCircleButton(size: 60, icon: Icons.play_arrow, onPressed: () {}),
    );

    expect(
      await cursorOver(tester, find.byIcon(Icons.play_arrow)),
      SystemMouseCursors.click,
    );
  });

  testWidgets('a disabled control keeps the plain arrow', (tester) async {
    await pump(
      tester,
      const AccentCircleButton(
        size: 60,
        icon: Icons.play_arrow,
        onPressed: null,
      ),
    );

    // A hand over something that does nothing when clicked is a lie about
    // what the control will do.
    expect(
      await cursorOver(tester, find.byIcon(Icons.play_arrow)),
      SystemMouseCursors.basic,
    );
  });

  testWidgets('a transport button', (tester) async {
    await pump(
      tester,
      TransportButton(
        icon: Icons.skip_next,
        size: 26,
        onPressed: () {},
        tooltip: 'Next',
      ),
    );

    expect(
      await cursorOver(tester, find.byIcon(Icons.skip_next)),
      SystemMouseCursors.click,
    );
  });

  testWidgets('the window chrome back chevron', (tester) async {
    await pump(
      tester,
      SizedBox(
        width: 800,
        child: WindowChrome(label: 'x', onBack: () {}),
      ),
    );

    expect(
      await cursorOver(tester, find.byTooltip('Back (Esc)')),
      SystemMouseCursors.click,
    );
  });

  testWidgets('a window control', (tester) async {
    await pump(
      tester,
      const SizedBox(width: 800, child: WindowChrome(label: 'x')),
    );

    expect(
      await cursorOver(tester, find.byTooltip('Close')),
      SystemMouseCursors.click,
    );
  });
}
