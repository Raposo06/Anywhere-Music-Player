import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

void main() {
  final api = SubsonicApiService(
    serverUrl: 'https://navidrome.example.com',
    username: 'alice',
    password: 'secret',
  );

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
      }, api);

      expect(track.id, '42');
      expect(track.title, 'A Song');
      expect(track.filename, 'Artist/Album/01 - A Song.flac');
      expect(track.folderPath, 'Artist/Album');
      expect(track.folderName, 'Album');
      expect(track.coverArtId, 'cov-42');
      expect(track.durationSeconds, 245);
      expect(track.fileSizeBytes, 12345678);
      expect(track.artist, 'An Artist');
      expect(track.album, 'An Album');
      expect(track.replayGainDb, -6.5);
      // streamUrl/coverArtUrl are derived, not asserted byte-for-byte here —
      // covered by SubsonicApiService's own URL-building tests.
      expect(track.streamUrl, contains('/rest/stream?id=42'));
      expect(track.coverArtUrl, contains('/rest/getCoverArt?id=cov-42'));
    });

    test('falls back sensibly when optional fields are missing', () {
      final track = Track.fromSubsonic({'id': '1', 'title': 'Untitled'}, api);

      expect(track.folderPath, '');
      expect(track.folderName, '');
      expect(track.coverArtId, isNull);
      expect(track.coverArtUrl, isNull);
      expect(track.durationSeconds, isNull);
      expect(track.replayGainDb, isNull);
    });

    test('defaults title to Unknown and derives a filename when both are absent', () {
      final track = Track.fromSubsonic({'id': '1'}, api);

      expect(track.title, 'Unknown');
      expect(track.filename, 'unknown.mp3');
    });

    test('respects an explicit parentFolderName override', () {
      final track = Track.fromSubsonic(
        {'id': '1', 'title': 'T', 'path': 'A/B/song.mp3'},
        api,
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
      }, api);

      final json = track.toJson();

      expect(json.containsKey('stream_url'), isFalse);
      expect(json.containsKey('cover_art_url'), isFalse);
      expect(json['cover_art_id'], 'cov-1');
    });

    test('fromJson reconstructs the track and recomputes URLs from the live api', () {
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
      }, api);

      final json = original.toJson();
      final restored = Track.fromJson(json, api: api);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.filename, original.filename);
      expect(restored.folderPath, original.folderPath);
      expect(restored.coverArtId, original.coverArtId);
      expect(restored.durationSeconds, original.durationSeconds);
      expect(restored.fileSizeBytes, original.fileSizeBytes);
      expect(restored.artist, original.artist);
      expect(restored.album, original.album);
      expect(restored.replayGainDb, original.replayGainDb);
      // Re-derived, not persisted — but still populated because `api` was
      // supplied at load time.
      expect(restored.streamUrl, contains('/rest/stream?id=7'));
      expect(restored.coverArtUrl, contains('/rest/getCoverArt?id=cov-7'));
    });

    test('fromJson tolerates a missing/unparseable created_at', () {
      final restored = Track.fromJson({
        'id': '1',
        'title': 'T',
        'filename': 'f.mp3',
        'folder_path': '',
      }, api: api);

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

  group('coverUrl / coverCacheKey', () {
    test('coverUrl appends &size= only when size is requested', () {
      final track = Track.fromSubsonic(
        {'id': '1', 'title': 'T', 'coverArt': 'cov-1'},
        api,
      );

      expect(track.coverUrl(), track.coverArtUrl);
      expect(track.coverUrl(size: 300), '${track.coverArtUrl}&size=300');
    });

    test('coverUrl and coverCacheKey are null without cover art', () {
      final track = Track.fromSubsonic({'id': '1', 'title': 'T'}, api);

      expect(track.coverUrl(), isNull);
      expect(track.coverCacheKey(), isNull);
    });

    test('coverCacheKey is stable and keyed on the id, not the (salt-rotating) URL', () {
      final track = Track.fromSubsonic(
        {'id': '1', 'title': 'T', 'coverArt': 'cov-99'},
        api,
      );

      expect(track.coverCacheKey(), 'cover_cov-99_full');
      expect(track.coverCacheKey(size: 300), 'cover_cov-99_300');
    });
  });
}

Track _trackWithDuration(int? seconds) => Track(
  id: '1',
  title: 'T',
  filename: 'f.mp3',
  streamUrl: 'https://x/stream',
  folderPath: '',
  createdAt: DateTime(2024),
  durationSeconds: seconds,
);

Track _trackWithFileSize(int? bytes) => Track(
  id: '1',
  title: 'T',
  filename: 'f.mp3',
  streamUrl: 'https://x/stream',
  folderPath: '',
  createdAt: DateTime(2024),
  fileSizeBytes: bytes,
);
