import 'package:flutter/foundation.dart';

/// One-shot messages for the user, from any module, shown once, somewhere.
///
/// The rule that decides what goes here: **a fetch that failed is state, a
/// mutation that failed is a notice.** A screen that could not load shows
/// the reason in place, with a Retry, from its module's own `error` — that
/// is state, it stays until the next attempt. A star that the server
/// refused, a playlist rename that bounced, a background refresh that could
/// not reach the server, a stream that dropped: the change already rolled
/// back or the cached data is still on screen, and all the user needs is to
/// be told, once, wherever they are. Those come here.
///
/// Before this existed each module kept its own sticky field
/// (`lastError`, `refreshError`, a `LoadStatus.error` doing double duty) and
/// each screen wrote its own listener to show and clear it — three
/// listeners for four modules, so playlist mutations were never shown at
/// all and a playback error was only visible while Now Playing was up.
/// See docs/decisions.md, 2026-09-13.
///
/// Modules push with [notice]. One widget in the shell — `NoticesListener`
/// — watches this, drains [take] after the frame and shows each message on
/// the app-level `ScaffoldMessenger`. Nothing else reads it.
class Notices with ChangeNotifier {
  final List<String> _pending = [];

  /// Kept from growing without bound when nothing is draining (tests, or a
  /// tree without the listener). Well above anything a user could see.
  static const _cap = 20;

  /// Messages pushed and not yet taken.
  List<String> get pending => List.unmodifiable(_pending);

  void notice(String message) {
    _pending.add(message);
    if (_pending.length > _cap) _pending.removeAt(0);
    notifyListeners();
  }

  /// Hand over everything pending and forget it. Does not notify — the
  /// listener calls this from its own build cycle, and a notification here
  /// would just schedule another one.
  List<String> take() {
    final out = List.of(_pending);
    _pending.clear();
    return out;
  }
}
