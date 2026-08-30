import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/widgets/desktop/desktop_shortcuts.dart';
import '../support/fake_just_audio.dart';
import '../support/fake_resolver.dart';
import '../support/fixtures.dart';

// Covers the desktop window-level keyboard shortcuts: that each binding
// reaches the player, and — the part most likely to regress — that none of
// them fire while a text field has focus, so a space typed into the search box
// doesn't pause the music.
//
// Driven against the same FakeJustAudioPlatform the service tests use, so no
// real audio backend is needed. These are the first widget tests for the
// desktop layouts (see docs/overview.md's "remaining gaps").
//
// Two things this file has to work around, both about async:
//   * Starting playback and seeking go through just_audio's platform
//     interface, whose futures do not complete under the widget tester's fake
//     async — hence [settle], which runs a real delay via runAsync. Volume and
//     track selection update synchronously and need only a pump.
//   * The service holds a periodic position timer (the scrobble watcher) while
//     playing, and testWidgets fails a test that ends with a timer pending —
//     hence disposing the service inside the test body rather than only in
//     tearDown.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  late FakeJustAudioPlatform fakePlatform;
  late AudioPlayerService service;
  var disposed = false;

  setUp(() {
    fakePlatform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = fakePlatform;
    service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    disposed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, (call) async => null);
  });

  /// Idempotent: tests call this before they end (so no timer is left
  /// pending), and tearDown catches the ones that failed before getting there.
  void disposeService() {
    if (disposed) return;
    disposed = true;
    service.dispose();
  }

  tearDown(() {
    disposeService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, null);
  });

  /// Lets real async work (a platform call, a debounce) finish. See the note
  /// at the top of the file.
  Future<void> settle(
    WidgetTester tester, [
    Duration wait = const Duration(milliseconds: 120),
  ]) async {
    await tester.runAsync(() => Future<void>.delayed(wait));
    await tester.pump();
  }

  Future<void> pumpShortcuts(
    WidgetTester tester, {
    Widget? child,
    VoidCallback? onBack,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AudioPlayerService>.value(
        value: service,
        child: MaterialApp(
          home: DesktopPlaybackShortcuts(
            onBack: onBack,
            child: child ?? const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Starts a three-track playlist, so seek and skip have something to act on.
  Future<void> startTrack(WidgetTester tester) async {
    await tester.runAsync(() async {
      await service.play([
        sampleTrack(id: 'a'),
        sampleTrack(id: 'b'),
        sampleTrack(id: 'c'),
      ], from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
  }

  testWidgets('space toggles play/pause', (tester) async {
    await pumpShortcuts(tester);
    await startTrack(tester);
    expect(service.isPlaying, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(service.isPlaying, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(service.isPlaying, isTrue);

    disposeService();
  });

  testWidgets('up and down arrows change the volume', (tester) async {
    await pumpShortcuts(tester);
    await startTrack(tester);
    expect(service.volume, 1.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(service.volume, closeTo(0.95, 0.0001));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(service.volume, closeTo(1.0, 0.0001));

    disposeService();
  });

  testWidgets('volume clamps at the top instead of overshooting', (
    tester,
  ) async {
    await pumpShortcuts(tester);
    await startTrack(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(service.volume, 1.0);
    disposeService();
  });

  testWidgets('right arrow seeks forward ten seconds', (tester) async {
    await pumpShortcuts(tester);
    await startTrack(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);

    final seek = fakePlatform.player.lastSeekPosition;
    expect(seek, isNotNull);
    // Position has advanced a little by now, so assert the jump, not equality.
    expect(seek!.inSeconds, greaterThanOrEqualTo(10));
    expect(seek.inSeconds, lessThan(15));

    disposeService();
  });

  testWidgets('left arrow near the start clamps to zero, never negative', (
    tester,
  ) async {
    await pumpShortcuts(tester);
    await startTrack(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);

    expect(fakePlatform.player.lastSeekPosition, Duration.zero);
    disposeService();
  });

  testWidgets('ctrl+right skips to the next track', (tester) async {
    await pumpShortcuts(tester);
    await startTrack(tester);
    expect(service.currentTrack?.id, 'a');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // Skips are debounced (see AudioPlayerService._skipDebounce), but the
    // shown track updates immediately.
    expect(service.currentTrack?.id, 'b');

    await settle(tester, const Duration(milliseconds: 400));
    disposeService();
  });

  testWidgets('ctrl+left goes back a track', (tester) async {
    await pumpShortcuts(tester);
    await startTrack(tester);

    await tester.runAsync(() async {
      await service.playNext();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    expect(service.currentTrack?.id, 'b');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(service.currentTrack?.id, 'a');

    await settle(tester, const Duration(milliseconds: 400));
    disposeService();
  });

  testWidgets('escape goes back where a handler is given', (tester) async {
    var back = 0;
    await pumpShortcuts(tester, onBack: () => back++);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(back, 1);
    disposeService();
  });

  testWidgets('alt+left goes back too', (tester) async {
    var back = 0;
    await pumpShortcuts(tester, onBack: () => back++);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(back, 1);
    disposeService();
  });

  testWidgets('alt+left goes back rather than seeking', (tester) async {
    // SingleActivator matches modifiers exactly, so the plain-arrow seek
    // binding must not also fire — that is what keeps the two apart.
    var back = 0;
    await pumpShortcuts(tester, onBack: () => back++);
    await startTrack(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await settle(tester);

    expect(back, 1);
    expect(fakePlatform.player.lastSeekPosition, isNull);
    disposeService();
  });

  testWidgets('back keys are inert where no handler is given', (tester) async {
    // A destination with nothing to go back through passes none.
    await pumpShortcuts(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(tester.takeException(), isNull);
    disposeService();
  });

  group('while a text field has focus', () {
    late FocusNode fieldFocus;

    setUp(() => fieldFocus = FocusNode());
    tearDown(() => fieldFocus.dispose());

    /// Pumps a focused text field inside the shortcut scope — the search
    /// box's shape, which is what the typing guard exists for.
    ///
    /// The field is focused explicitly rather than with `autofocus`: the
    /// shortcut wrapper's own focus holder claims autofocus (see
    /// DesktopPlaybackShortcuts), so an autofocusing field here would not
    /// reliably win, and the test would pass for the wrong reason.
    Future<void> pumpFocusedField(
      WidgetTester tester, {
      VoidCallback? onBack,
    }) async {
      await pumpShortcuts(
        tester,
        onBack: onBack,
        child: Scaffold(body: TextField(focusNode: fieldFocus)),
      );
      fieldFocus.requestFocus();
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
        reason: 'the field must really hold focus or this proves nothing',
      );
    }

    testWidgets('space does not toggle playback', (tester) async {
      await pumpFocusedField(tester);
      await startTrack(tester);
      fieldFocus.requestFocus();
      await tester.pump();
      expect(service.isPlaying, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);

      expect(service.isPlaying, isTrue);
      disposeService();
    });

    testWidgets('arrows do not change the volume', (tester) async {
      await pumpFocusedField(tester);
      await startTrack(tester);
      fieldFocus.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(service.volume, 1.0);
      disposeService();
    });

    testWidgets('the back keys do not fire', (tester) async {
      var back = 0;
      await pumpFocusedField(tester, onBack: () => back++);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      expect(back, 0);
      disposeService();
    });
  });
}
