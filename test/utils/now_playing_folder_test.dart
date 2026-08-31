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
    test('drops the top-level category segment', () {
      expect(
        nowPlayingFolderPath(_track(
          'SOUNDTRACKS/MOVIES & SERIES/Harry Potter/Philosophers Stone',
        )),
        'MOVIES & SERIES/Harry Potter/Philosophers Stone',
      );
    });

    test('drops the first segment of a tag-based path too', () {
      expect(
        nowPlayingFolderPath(_track('John Williams/Philosophers Stone')),
        'Philosophers Stone',
      );
    });

    test('is empty when only the top-level segment exists', () {
      expect(nowPlayingFolderPath(_track('SOUNDTRACKS')), '');
    });

    test('is empty for a track with no folder', () {
      expect(nowPlayingFolderPath(_track('')), '');
    });
  });
}
