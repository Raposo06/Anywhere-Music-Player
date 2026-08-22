import 'dart:async';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// Fake [JustAudioPlatform] — stands in for the real native just_audio
/// backend (ExoPlayer on Android, media_kit on Windows/Linux) so
/// AudioPlayerService's playback methods (playTrack, playNext, stop, seek,
/// ...) can run under `flutter test` without a live platform audio backend.
///
/// Register once per test, before constructing any AudioPlayerService:
/// `JustAudioPlatform.instance = FakeJustAudioPlatform();`
///
/// Trimmed down from the shape of just_audio's own test double
/// (MockAudioPlayer in its package tests) to what AudioPlayerService
/// actually calls, plus test hooks — [FakeAudioPlayerPlatform.failNextLoadWith],
/// [FakeAudioPlayerPlatform.completeTrack], [FakeAudioPlayerPlatform.injectStreamError] —
/// that let tests drive the scenarios AudioPlayerService is meant to handle
/// (a load failure, natural end-of-track, a mid-stream drop).
class FakeJustAudioPlatform extends JustAudioPlatform {
  final players = <String, FakeAudioPlayerPlatform>{};

  /// The most recently init()'d player — convenient when a test only cares
  /// about the one AudioPlayerService under test creates (AudioPlayerService
  /// only ever holds one AudioPlayer at a time).
  FakeAudioPlayerPlatform get player => players.values.last;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final p = FakeAudioPlayerPlatform(request.id);
    players[request.id] = p;
    return p;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    players.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    players.clear();
    return DisposeAllPlayersResponse();
  }
}

class FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  FakeAudioPlayerPlatform(super.id);

  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _eventController.stream;

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  static const _defaultDuration = Duration(minutes: 3);

  /// Every uri passed to [load], in call order — lets a test assert which
  /// tracks were actually opened, and how many times (e.g. debounce
  /// coalescing, or a repeat-one reload of the same track).
  final loadedUris = <String>[];
  int get loadCount => loadedUris.length;

  double? lastVolume;
  Duration? lastSeekPosition;

  /// Test hook: makes the next [load] throw, simulating a stream-open
  /// failure (bad URL, server error).
  Object? failNextLoadWith;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final src = request.audioSourceMessage;
    if (src is UriAudioSourceMessage) loadedUris.add(src.uri);

    if (failNextLoadWith != null) {
      final err = failNextLoadWith!;
      failNextLoadWith = null;
      throw err;
    }

    _processingState = ProcessingStateMessage.ready;
    _emit();
    return LoadResponse(duration: _defaultDuration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    lastSeekPosition = request.position;
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    lastVolume = request.volume;
    return SetVolumeResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
    SetShuffleOrderRequest request,
  ) async => SetShuffleOrderResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async => SetSkipSilenceResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async => SetAndroidAudioAttributesResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
  setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _processingState = ProcessingStateMessage.idle;
    return DisposeResponse();
  }

  /// Simulates natural end-of-track: the platform reports `completed`, which
  /// is what AudioPlayerService's playerStateStream listener reacts to by
  /// advancing to the next track.
  void completeTrack() {
    _processingState = ProcessingStateMessage.completed;
    _emit();
  }

  /// Simulates a mid-stream drop: an error on the playback event stream —
  /// what AudioPlayerService._handleStreamError reacts to.
  void injectStreamError(Object error) => _eventController.addError(error);

  void _emit() {
    _eventController.add(
      PlaybackEventMessage(
        processingState: _processingState,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: _defaultDuration,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ),
    );
  }
}
