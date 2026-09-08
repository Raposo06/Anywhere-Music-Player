import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/models/track.dart';

void main() {
  group('Track.fromSubsonic', () {
    test('parses a well-formed song response', () {
      final track = Track.fromSubsonic({
        'id': '42',
        'title': 'A Song',
        'path': 'Artist/Album/01 - A Song.flac',
        'coverArt': 'cov-42',
        'duration': 245,
        'size': 12345678,
        'created': '2024-01-15T10:00:00Z',
        'artist': 'An Artist',
        'album': 'An Album',
        'replayGain': {'trackGain': -6.5},
      });

      expect(track.id, '42');
      expect(track.title, 'A Song');
      expect(track.path, 'Artist/Album/01 - A Song.flac');
      expect(track.folderPath, 'Artist/Album');
      expect(track.folderName, 'Album');
      expect(track.coverArtId, 'cov-42');
      expect(track.durationSeconds, 245);
      expect(track.fileSizeBytes, 12345678);
      expect(track.artist, 'An Artist');
      expect(track.album, 'An Album');
      expect(track.replayGainDb, -6.5);
      // No streamUrl/coverArtUrl to assert — resolved on demand at the point
      // of use instead (see StreamUrlResolver, and its own test file for the
      // URL-building coverage).
    });

    test('falls back sensibly when optional fields are missing', () {
      final track = Track.fromSubsonic({'id': '1', 'title': 'Untitled'});

      expect(track.folderPath, '');
      expect(track.folderName, '');
      expect(track.coverArtId, isNull);
      expect(track.durationSeconds, isNull);
      expect(track.replayGainDb, isNull);
    });

    test('defaults title to Unknown, and leaves path empty rather than synthesizing one', () {
      // Was: falls back to a filename-shaped string ('unknown.mp3') that
      // looked like real data. An empty path is honest about "we don't know"
      // and matches folderPath/folderName's own empty-string convention.
      final track = Track.fromSubsonic({'id': '1'});

      expect(track.title, 'Unknown');
      expect(track.path, '');
    });

    test('respects an explicit parentFolderName override', () {
      final track = Track.fromSubsonic(
        {'id': '1', 'title': 'T', 'path': 'A/B/song.mp3'},
        parentFolderName: 'Custom Name',
      );

      expect(track.folderName, 'Custom Name');
    });
  });

  group('Track.fromSubsonic with a pathOverride', () {
    // The folder walk synthesizes each song's path from the directories it
    // descended through and passes it here, because that path — not the
    // server's own `path` field — is the tree the app actually browsed.
    test('the override supplies path, folderPath and folderName', () {
      final track = Track.fromSubsonic(
        {'id': '42', 'title': 'A Song', 'coverArt': 'cov-42', 'duration': 245},
        pathOverride: 'Artist/Album/01 - A Song.flac',
      );

      expect(track.path, 'Artist/Album/01 - A Song.flac');
      expect(track.folderPath, 'Artist/Album');
      expect(track.folderName, 'Album');
      expect(track.coverArtId, 'cov-42');
      expect(track.durationSeconds, 245);
    });

    test('the override wins over the path the server sent', () {
      // Gonic's own `path` may be relative to a music folder this walk has
      // already accounted for, so the two can legitimately disagree. The
      // walk's answer is the one the folder tree has to agree with.
      final track = Track.fromSubsonic(
        {'id': '1', 'title': 'T', 'path': 'somewhere/else/song.mp3'},
        pathOverride: 'Anime/Naruto/song.mp3',
      );

      expect(track.path, 'Anime/Naruto/song.mp3');
      expect(track.folderPath, 'Anime/Naruto');
    });

    test('a root-level override leaves folderPath empty, not guessed', () {
      final track = Track.fromSubsonic(
        {'id': '1', 'title': 'T'},
        pathOverride: 'loose-track.mp3',
      );

      expect(track.path, 'loose-track.mp3');
      expect(track.folderPath, '');
      expect(track.folderName, '');
    });

    test('parentFolderName still wins over the override-derived name', () {
      final track = Track.fromSubsonic(
        {'id': '1', 'title': 'T'},
        pathOverride: 'A/B/song.mp3',
        parentFolderName: 'Custom Name',
      );

      expect(track.folderName, 'Custom Name');
    });
  });

  group('Track JSON round-trip (library cache)', () {
    test('toJson never includes streamUrl or coverArtUrl', () {
      final track = Track.fromSubsonic({
        'id': '1',
        'title': 'T',
        'coverArt': 'cov-1',
        'path': 'A/song.mp3',
      });

      final json = track.toJson();

      expect(json.containsKey('stream_url'), isFalse);
      expect(json.containsKey('cover_art_url'), isFalse);
      expect(json['cover_art_id'], 'cov-1');
    });

    test('fromJson reconstructs the track', () {
      final original = Track.fromSubsonic({
        'id': '7',
        'title': 'Round Trip',
        'coverArt': 'cov-7',
        'path': 'Artist/Album/track.flac',
        'duration': 200,
        'size': 999,
        'created': '2023-05-01T00:00:00Z',
        'artist': 'Artist',
        'album': 'Album',
        'replayGain': {'trackGain': -3.0},
      });

      final json = original.toJson();
      final restored = Track.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.path, original.path);
      expect(restored.folderPath, original.folderPath);
      expect(restored.coverArtId, original.coverArtId);
      expect(restored.durationSeconds, original.durationSeconds);
      expect(restored.fileSizeBytes, original.fileSizeBytes);
      expect(restored.artist, original.artist);
      expect(restored.album, original.album);
      expect(restored.replayGainDb, original.replayGainDb);
    });

    test('fromJson tolerates a missing/unparseable created_at', () {
      final restored = Track.fromJson({
        'id': '1',
        'title': 'T',
        'path': 'f.mp3',
        'folder_path': '',
      });

      expect(restored.createdAt, isA<DateTime>());
    });
  });

  group('formattedDuration', () {
    test('renders MM:SS under an hour', () {
      final t = _trackWithDuration(125); // 2:05
      expect(t.formattedDuration, '02:05');
    });

    test('renders H:MM:SS at an hour or more', () {
      final t = _trackWithDuration(3725); // 1:02:05
      expect(t.formattedDuration, '1:02:05');
    });

    test('renders a placeholder when duration is unknown', () {
      final t = _trackWithDuration(null);
      expect(t.formattedDuration, '--:--');
    });
  });

  group('formattedFileSize', () {
    test('renders megabytes to one decimal place', () {
      final t = _trackWithFileSize(5 * 1024 * 1024);
      expect(t.formattedFileSize, '5.0 MB');
    });

    test('renders Unknown when size is unknown', () {
      final t = _trackWithFileSize(null);
      expect(t.formattedFileSize, 'Unknown');
    });
  });

  group('coverCacheKey', () {
    // coverUrl moved off the model entirely — see
    // test/services/stream_url_resolver_test.dart and
    // docs/reviews/2026-08-22-architecture-review.html Candidate 07.
    test('is null without cover art', () {
      final track = Track.fromSubsonic({'id': '1', 'title': 'T'});
      expect(track.coverCacheKey(), isNull);
    });

    test('is stable and keyed on the id, not a (salt-rotating) URL', () {
      final track = Track.fromSubsonic({'id': '1', 'title': 'T', 'coverArt': 'cov-99'});

      expect(track.coverCacheKey(), 'cover_cov-99_full');
      expect(track.coverCacheKey(size: 300), 'cover_cov-99_300');
    });
  });
}

Track _trackWithDuration(int? seconds) => Track(
  id: '1',
  title: 'T',
  path: 'f.mp3',
  folderPath: '',
  createdAt: DateTime(2024),
  durationSeconds: seconds,
);

Track _trackWithFileSize(int? bytes) => Track(
  id: '1',
  title: 'T',
  path: 'f.mp3',
  folderPath: '',
  createdAt: DateTime(2024),
  fileSizeBytes: bytes,
);
