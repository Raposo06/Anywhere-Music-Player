import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/models/folder.dart';

void main() {
  group('Folder.fromSubsonic', () {
    test('counts direct child songs over albumCount when children are present', () {
      final folder = Folder.fromSubsonic({
        'id': '1',
        'name': 'Album',
        'albumCount': 99,
        'child': [
          {'isDir': false},
          {'isDir': false},
          {'isDir': true},
        ],
      });

      expect(folder.trackCount, 2);
    });

    test('falls back to albumCount when there is no child list', () {
      final folder = Folder.fromSubsonic({
        'id': '1',
        'name': 'Artist',
        'albumCount': 5,
      });

      expect(folder.trackCount, 5);
      expect(folder.albumCount, 5);
    });

    test('normalizes a single child object into a one-item list', () {
      final folder = Folder.fromSubsonic({
        'id': '1',
        'name': 'Album',
        'child': {'isDir': false},
      });

      expect(folder.trackCount, 1);
    });

    test('prefers name over title, and falls back to Unknown', () {
      expect(Folder.fromSubsonic({'title': 'Fallback Title'}).folderPath, 'Fallback Title');
      expect(Folder.fromSubsonic({}).folderPath, 'Unknown');
    });

    test('extracts the coverArt id — no URL is resolved here (see StreamUrlResolver)', () {
      final folder = Folder.fromSubsonic({'name': 'A', 'coverArt': 'cov-1'});
      expect(folder.coverArtId, 'cov-1');
    });

    test('falls back to artistImageUrl for the cover id when coverArt is absent', () {
      final folder = Folder.fromSubsonic({'name': 'A', 'artistImageUrl': 'img-1'});
      expect(folder.coverArtId, 'img-1');
    });
  });

  group('path helpers', () {
    test('displayName is the last path segment', () {
      final folder = Folder(folderPath: 'Animes/Pokemon', trackCount: 0);
      expect(folder.displayName, 'Pokemon');
    });

    test('displayName is the whole path when there is no nesting', () {
      final folder = Folder(folderPath: 'Pokemon', trackCount: 0);
      expect(folder.displayName, 'Pokemon');
    });

    test('isRoot is true only without a path separator', () {
      expect(Folder(folderPath: 'Pokemon', trackCount: 0).isRoot, isTrue);
      expect(Folder(folderPath: 'Animes/Pokemon', trackCount: 0).isRoot, isFalse);
    });

    test('parentPath drops the last segment, or is null at the root', () {
      expect(Folder(folderPath: 'Animes/Pokemon', trackCount: 0).parentPath, 'Animes');
      expect(Folder(folderPath: 'Pokemon', trackCount: 0).parentPath, isNull);
    });
  });

  group('subtitle', () {
    test('prefers track count, then album count, else blank', () {
      expect(Folder(folderPath: 'A', trackCount: 3).subtitle, '3 track(s)');
      expect(Folder(folderPath: 'A', trackCount: 0, albumCount: 2).subtitle, '2 album(s)');
      expect(Folder(folderPath: 'A', trackCount: 0).subtitle, '');
    });
  });

  group('coverCacheKey', () {
    // coverUrl moved off the model entirely — see
    // test/services/stream_url_resolver_test.dart and
    // docs/reviews/2026-08-22-architecture-review.html Candidate 07.
    test('is size-qualified and keyed on the id', () {
      final folder = Folder(folderPath: 'A', trackCount: 0, coverArtId: 'cov-1');
      expect(folder.coverCacheKey(size: 300), 'cover_cov-1_300');
    });

    test('is null without cover art', () {
      final folder = Folder(folderPath: 'A', trackCount: 0);
      expect(folder.coverCacheKey(), isNull);
    });
  });
}
