import 'package:anywhere_music_player/services/playback_reporter.dart';

/// Records every report instead of reaching a real server — lets a test
/// assert "playing past the threshold scrobbles once" directly. Same shape as
/// [RecordingPresence] in fake_presence.dart.
class RecordingReporter implements PlaybackReporter {
  final List<String> nowPlayingIds = [];
  final List<({String id, DateTime? startedAt})> scrobbles = [];

  /// When set, both methods throw it — for asserting that a server which
  /// rejects (or doesn't implement) `/rest/scrobble` can't break playback.
  Object? failWith;

  @override
  Future<void> nowPlaying(String songId) async {
    if (failWith case final error?) throw error;
    nowPlayingIds.add(songId);
  }

  @override
  Future<void> scrobble(String songId, {DateTime? startedAt}) async {
    if (failWith case final error?) throw error;
    scrobbles.add((id: songId, startedAt: startedAt));
  }

  /// Ids scrobbled, in order — the assertion most tests actually want.
  List<String> get scrobbledIds => [for (final s in scrobbles) s.id];
}
