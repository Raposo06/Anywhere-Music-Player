import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/utils/now_playing_folder.dart';

Track _track(String folderPath) => Track(
  id: '1',
  title: 'Song',
  path: '$folderPath/song.flac',
  folderPath: folderPath,
  createdAt: DateTime(2024),
);

void main() {
  group('nowPlayingFolderPath', () {
    test('shows the full path, including the top-level category', () {
      expect(
        nowPlayingFolderPath(
          _track('ANIMES & ANIMATIONS/Bleach/Bleach Original Soundtrack 1'),
        ),
        'ANIMES & ANIMATIONS/Bleach/Bleach Original Soundtrack 1',
      );
    });

    test('keeps every segment of a deep path', () {
      expect(
        nowPlayingFolderPath(
          _track(
            'ANIMES & ANIMATIONS/Dragon Ball/Dragon Ball Z BGM Collection/Vol. 01',
          ),
        ),
        'ANIMES & ANIMATIONS/Dragon Ball/Dragon Ball Z BGM Collection/Vol. 01',
      );
    });

    test('a single-segment path still shows, rather than blanking the line', () {
      // Regression: the old drop-the-first-segment rule emptied this, hiding
      // the folder line for every track sitting directly in a category folder.
      expect(
        nowPlayingFolderPath(_track('MIXES & COMPILATIONS')),
        'MIXES & COMPILATIONS',
      );
    });

    test('is empty for a track with no folder', () {
      expect(nowPlayingFolderPath(_track('')), '');
    });
  });
}
