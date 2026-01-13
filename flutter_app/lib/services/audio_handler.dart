import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

/// Audio handler for system media controls (Windows taskbar, notifications, etc.)
class MusicAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player;
  final Function() onNext;
  final Function() onPrevious;

  MusicAudioHandler({
    required AudioPlayer player,
    required this.onNext,
    required this.onPrevious,
  }) : _player = player {
    // Broadcast player state to system media controls
    _player.playbackEventStream.listen(_broadcastState);

    // Broadcast processing state changes
    _player.playerStateStream.listen((state) {
      _broadcastState(_player.playbackEvent);
    });
  }

  /// Broadcast current playback state to system media controls
  void _broadcastState(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
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
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  /// Update metadata when track changes
  void updateTrackInfo(Track track) {
    mediaItem.add(MediaItem(
      id: track.id,
      title: track.title,
      artist: track.folderPath.isNotEmpty ? track.folderPath : 'Unknown Artist',
      duration: track.durationSeconds != null
          ? Duration(seconds: track.durationSeconds!)
          : null,
      artUri: track.coverArtUrl != null ? Uri.parse(track.coverArtUrl!) : null,
    ));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    onNext();
  }

  @override
  Future<void> skipToPrevious() async {
    onPrevious();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }
}
