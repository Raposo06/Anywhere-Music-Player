import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:just_audio/just_audio.dart';

import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/services/stream_cache.dart';

/// A [StreamCache] that stores nothing and records what it was asked to warm.
///
/// Behaves exactly like [DirectStreamCache] for playback, so a test using it
/// exercises the ordinary load path; the only difference is that [prefetched]
/// remembers the calls, which is what makes the prefetch trigger observable.
class RecordingStreamCache extends StreamCache {
  final List<String> prefetched = <String>[];
  final List<String> evictedKeeping = <String>[];

  @override
  Future<AudioSource> sourceFor(Track track, Uri uri, MediaItem tag) async =>
      AudioSource.uri(uri, tag: tag);

  @override
  Future<void> prefetch(Track track, Uri uri, MediaItem tag) async {
    prefetched.add(track.id);
  }

  @override
  Future<void> evict({required Track? keep}) async {
    evictedKeeping.add(keep?.id ?? '(none)');
  }
}
