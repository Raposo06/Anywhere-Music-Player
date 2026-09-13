import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/services/notices.dart';

// Covers Notices, the one-shot message queue every module pushes its failed
// mutations into and the shell's NoticesListener drains. Small on purpose:
// the contract is "push notifies, take drains silently, nothing grows
// without bound".
void main() {
  test('starts empty', () {
    expect(Notices().pending, isEmpty);
  });

  test('notice queues in order and notifies each time', () {
    final notices = Notices();
    var notified = 0;
    notices.addListener(() => notified++);

    notices.notice('first');
    notices.notice('second');

    expect(notices.pending, ['first', 'second']);
    expect(notified, 2);
  });

  test(
    'take hands everything over, empties the queue, and does not notify',
    () {
      final notices = Notices()
        ..notice('a')
        ..notice('b');
      var notified = 0;
      notices.addListener(() => notified++);

      expect(notices.take(), ['a', 'b']);
      expect(notices.pending, isEmpty);
      expect(notices.take(), isEmpty);
      expect(notified, 0);
    },
  );

  test('pending is a snapshot, not the live list', () {
    final notices = Notices()..notice('a');
    final seen = notices.pending;
    notices.notice('b');
    expect(seen, ['a']);
    expect(() => seen.add('x'), throwsUnsupportedError);
  });

  test('drops the oldest past the cap, so an undrained sink stays bounded', () {
    final notices = Notices();
    for (var i = 0; i < 25; i++) {
      notices.notice('$i');
    }
    expect(notices.pending, hasLength(20));
    expect(notices.pending.first, '5');
    expect(notices.pending.last, '24');
  });
}
