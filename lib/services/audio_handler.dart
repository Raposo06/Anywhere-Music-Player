import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/track.dart';
import 'stream_url_resolver.dart';

/// Audio handler for system media controls (notifications, lock screen, etc.)
///
/// Created early in main() via AudioService.init() with no player attached.
/// The AudioPlayer and callbacks are attached later by AudioPlayerService
/// via [attachPlayer].
class MusicAudioHandler extends BaseAudioHandler {
  AudioPlayer? _player;
  Function()? onNext;
  Function()? onPrevious;
  final StreamUrlResolver _resolver;

  // Monotonic counter bumped on every track change. Used as the playbackState
  // queueIndex so Bluetooth AVRCP (car head units) sees a new queue position
  // and fires TRACK_CHANGED. Without this, the car shows a stale title even
  // though the lock screen updates correctly.
  int _trackCounter = 0;

  // Cover size requested for system/car media metadata. Sized (not the full
  // master) so it downloads fast and stays small enough for head-unit displays.
  static const int _carArtSize = 512;

  MusicAudioHandler({required StreamUrlResolver resolver}) : _resolver = resolver {
    // Initialize with stopped state
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seek,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.idle,
      playing: false,
      updatePosition: Duration.zero,
      speed: 1.0,
    ));
  }

  /// Attach an AudioPlayer and callbacks after initialization.
  /// Called by AudioPlayerService once it has created its player.
  void attachPlayer({
    required AudioPlayer player,
    required Function() onNextCallback,
    required Function() onPreviousCallback,
  }) {
    _player = player;
    onNext = onNextCallback;
    onPrevious = onPreviousCallback;

    // Broadcast player state to system media controls
    _player!.playbackEventStream.listen(_broadcastState);

    // Broadcast processing state changes
    _player!.playerStateStream.listen((state) {
      _broadcastState(_player!.playbackEvent);
    });
  }

  /// Broadcast current playback state to system media controls
  void _broadcastState(PlaybackEvent event) {
    if (_player == null) return;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_player!.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player!.processingState]!,
      playing: _player!.playing,
      updatePosition: _player!.position,
      bufferedPosition: _player!.bufferedPosition,
      speed: _player!.speed,
      // Intentionally not setting queueIndex here — it's managed by
      // updateTrackInfo (synthetic counter for AVRCP). event.currentIndex is
      // always 0 in single-source mode and would clobber our value.
    ));
  }

  /// Update metadata when the track changes.
  ///
  /// Resolves the cover to a LOCAL file *before* publishing so the artwork is
  /// embedded in the very first metadata push — and in the AVRCP TRACK_CHANGED
  /// that follows it. Car head units only re-read artwork on a track/state
  /// change, so a cover that finishes downloading *after* the push otherwise
  /// doesn't appear until the user pauses and resumes. Falls back to the remote
  /// URL if the file can't be fetched (e.g. offline).
  Future<void> updateTrackInfo(Track track) async {
    final artUrl = _resolver.resolveCoverUrl(track, size: _carArtSize);

    Uri? artUri;
    if (artUrl != null) {
      try {
        // Returns instantly if already cached, otherwise downloads once.
        // Keyed by the stable coverArtId (not the URL, whose auth salt
        // rotates every rebuild) so re-scans don't force a re-download.
        final file = await DefaultCacheManager().getSingleFile(
          artUrl,
          key: track.coverCacheKey(size: _carArtSize),
        );
        artUri = Uri.file(file.path);
      } catch (_) {
        artUri = Uri.tryParse(artUrl);
      }
    }

    final item = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist ?? '',
      album: track.album ?? '',
      duration: track.durationSeconds != null
          ? Duration(seconds: track.durationSeconds!)
          : null,
      artUri: artUri,
    );

    mediaItem.add(item);

    // Bump the synthetic queue index. The car's Bluetooth stack uses this
    // change as the trigger to refresh the displayed title (and now art).
    _trackCounter++;
    queue.add([item]);
    playbackState.add(playbackState.value.copyWith(queueIndex: _trackCounter));
  }

  @override
  Future<void> play() async {
    await _player?.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onPrevious?.call();
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    await super.stop();
  }

  /// Called by Android when the user swipes the app away from recents.
  /// Default audio_service behaviour is to keep the foreground service alive
  /// so audio can keep playing — we override that to fully tear down so the
  /// notification disappears and the process can exit.
  @override
  Future<void> onTaskRemoved() async {
    await _player?.stop();
    await stop();
    await super.onTaskRemoved();
  }
}
