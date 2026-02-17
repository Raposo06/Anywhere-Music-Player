import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

/// Audio handler for system media controls (notifications, lock screen, etc.)
///
/// Created early in main() via AudioService.init() with no player attached.
/// The AudioPlayer and callbacks are attached later by AudioPlayerService
/// via [attachPlayer].
class MusicAudioHandler extends BaseAudioHandler {
  AudioPlayer? _player;
  Function()? onNext;
  Function()? onPrevious;

  MusicAudioHandler() {
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
      queueIndex: event.currentIndex,
    ));
  }

  /// Update metadata when track changes
  void updateTrackInfo(Track track) {
    final item = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.folderPath.isNotEmpty ? track.folderPath : 'Unknown Artist',
      duration: track.durationSeconds != null
          ? Duration(seconds: track.durationSeconds!)
          : null,
      artUri: track.coverArtUrl != null ? Uri.parse(track.coverArtUrl!) : null,
    );

    mediaItem.add(item);
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
}
