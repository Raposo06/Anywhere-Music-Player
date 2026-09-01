import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bounded alternative to [WidgetTester.pumpAndSettle] for screens built on
/// [ScrollablePositionedList] (the folder screens): that widget's
/// internal re-measurement can keep scheduling frames indefinitely, which
/// makes `pumpAndSettle()` hang rather than time out. This just advances a
/// fixed amount of simulated time instead of waiting for "no more frames".
Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits out async work a widget kicked off itself (e.g. HomeScreen's
/// initState calling LibraryScanner.scan(), which spawns a real isolate via
/// compute()). testWidgets() runs test bodies in a fake-async zone that never
/// delivers a real isolate's response, so plain pump()/pumpAndSettle() hangs
/// forever on it — this pumps one frame to let the work start, then escapes
/// into tester.runAsync (the documented way to let real async/isolate work
/// resolve inside a widget test) and polls [isBusy] until it clears.
Future<void> waitForAsyncWork(WidgetTester tester, bool Function() isBusy) async {
  // The pump that fires the postFrameCallback (and the scan() it kicks off)
  // must itself happen inside runAsync: a Future's continuation stays bound
  // to the zone it was *created* in, so a plain pump() outside runAsync
  // creates a scan() permanently stuck in the fake-async zone — no amount of
  // polling from runAsync afterward can rescue it.
  await tester.runAsync(() async {
    await tester.pump();
    while (isBusy()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}

/// Like [waitForAsyncWork], but for a widget whose *first* build (in
/// initState) kicks off the async work — e.g. HomeScreen calling
/// LibraryScanner.scan() from a postFrameCallback registered during
/// initState. That callback fires as part of pumpWidget() itself, so the
/// pumpWidget() call has to be the thing running inside runAsync, not a
/// pump() after it (by then the callback — and the zone-bound scan() it
/// started — has already fired outside runAsync).
Future<void> pumpAndWaitForAsyncWork(
  WidgetTester tester,
  Widget widget,
  bool Function() isBusy,
) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(widget);
    while (isBusy()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}
