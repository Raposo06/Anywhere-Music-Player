import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/models/subsonic_json.dart';

// The single-element collapse is the wire quirk that used to be re-derived at
// six call sites. It lives here now, so it is pinned here.
void main() {
  test('a real list passes through untouched', () {
    expect(subsonicList([1, 2, 3]), [1, 2, 3]);
  });

  test('a bare object becomes a one-element list', () {
    expect(subsonicList({'id': '1'}), [
      {'id': '1'},
    ]);
  });

  test('an absent field is the empty list, not null', () {
    expect(subsonicList(null), isEmpty);
    expect(subsonicList(<String, dynamic>{}['child']), isEmpty);
  });

  test('an empty list stays empty', () {
    expect(subsonicList([]), isEmpty);
  });
}
