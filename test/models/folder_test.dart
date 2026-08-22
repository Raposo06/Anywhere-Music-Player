import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/models/folder.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

void main() {
  final api = SubsonicApiService(
    serverUrl: 'https://navidrome.example.com',
    username: 'alice',
    password: 'secret',
  );

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

    test('resolves coverArtUrl only when both coverArt id and api are given', () {
      final withApi = Folder.fromSubsonic({'name': 'A', 'coverArt': 'cov-1'}, api: api);
      final withoutApi = Folder.fromSubsonic({'name': 'A', 'coverArt': 'cov-1'});

      expect(withApi.coverArtUrl, isNotNull);
      expect(withApi.coverArtId, 'cov-1');
      expect(withoutApi.coverArtUrl, isNull);
      expect(withoutApi.coverArtId, 'cov-1');
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

  group('coverUrl / coverCacheKey', () {
    test('mirrors Track: size-qualified URL and id-keyed cache key', () {
      final folder = Folder(
        folderPath: 'A',
        trackCount: 0,
        coverArtUrl: 'https://x/rest/getCoverArt?id=cov-1&u=a&t=b&s=c',
        coverArtId: 'cov-1',
      );

      expect(folder.coverUrl(size: 300), '${folder.coverArtUrl}&size=300');
      expect(folder.coverCacheKey(size: 300), 'cover_cov-1_300');
    });

    test('are null without cover art', () {
      final folder = Folder(folderPath: 'A', trackCount: 0);
      expect(folder.coverUrl(), isNull);
      expect(folder.coverCacheKey(), isNull);
    });
  });
}
