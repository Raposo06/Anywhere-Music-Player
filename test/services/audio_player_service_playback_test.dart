import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import '../support/fake_just_audio.dart';
import '../support/fake_presence.dart';
import '../support/fake_resolver.dart';
import '../support/fixtures.dart';

// Covers AudioPlayerService's playback entry points — playTrack/play/
// playNext/playPrevious/stop/seek/setVolume/togglePlayPause — plus natural
// end-of-track advance, repeat-one looping, skip-debounce coalescing, a load
// failure, and mid-stream drop recovery. Exercised against a
// FakeJustAudioPlatform (test/support/fake_just_audio.dart) standing in for
// the real native backend (media_kit on Windows, ExoPlayer on Android) that
// `flutter test` doesn't provide. See playback_cursor_test.dart for the pure
// index/shuffle math this complements, and docs/operations.md for why the two
// platforms still need real-device testing on top of this.
//
// AudioPlayerService() defaults to NoPresence (see NowPlayingPresence), so
// none of this needs a real Windows/Android platform channel — that used to
// require mocking window_manager here purely to stop an unrelated test from
// throwing. See docs/reviews/2026-08-22-architecture-review.html Candidate 06.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // just_audio activates an OS audio session via this channel on every
  // play() call — unmocked, that's a MissingPluginException on an unawaited
  // Future (AudioPlayerService never awaits play()), which surfaces as an
  // unhandled test error.
  const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  late FakeJustAudioPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = fakePlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, null);
  });

  /// Polls until [test] is true — used instead of a fixed delay to wait out
  /// the async gap between calling a play method and AudioPlayerService's
  /// state (load, volume, isLoading) actually settling.
  Future<void> waitUntil(
    bool Function() test, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    // do-while, not while: always wait at least one real tick before the
    // first check. A plain `while` checks synchronously before this call
    // yields at all — if the state change comes from an event fired just
    // before calling this (e.g. injectStreamError, which delivers via a
    // non-sync broadcast StreamController and so needs a microtask to even
    // reach its listener), the check can pass before that event has been
    // processed at all, and the caller moves on having not actually waited.
    do {
      if (DateTime.now().isAfter(deadline)) fail('waitUntil timed out');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    } while (!test());
  }

  test('playTrack loads and plays, applying ReplayGain to the volume', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());

    await service.playTrack(sampleTrack(id: '1', replayGainDb: -7.0));
    await waitUntil(() => !service.isLoading);

    expect(service.currentTrack?.id, '1');
    expect(service.isPlaying, isTrue);
    expect(fakePlatform.player.loadCount, 1);
    expect(fakePlatform.player.lastVolume, closeTo(0.89, 0.01)); // -7dB @ +6dB preamp
  });

  test('play starts at the given index', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    final tracks = [sampleTrack(id: '1'), sampleTrack(id: '2'), sampleTrack(id: '3')];

    await service.play(tracks, from: 2);
    await waitUntil(() => !service.isLoading);

    expect(service.currentIndex, 2);
    expect(service.currentTrack?.id, '3');
  });

  test('playNext debounces a burst of skips into a single load', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    final tracks = [sampleTrack(id: '1'), sampleTrack(id: '2'), sampleTrack(id: '3')];
    await service.play(tracks, from: 0);
    await waitUntil(() => !service.isLoading);
    expect(fakePlatform.player.loadCount, 1);

    await service.playNext();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await service.playNext();

    // Shown track updates per press...
    expect(service.currentTrack?.id, '3');
    // ...but the stream isn't opened until the debounce settles.
    expect(fakePlatform.player.loadCount, 1);

    await Future<void>.delayed(const Duration(milliseconds: 300)); // past the 280ms debounce
    await waitUntil(() => !service.isLoading);

    // Only the track the user landed on was opened — not track 2 as well.
    expect(fakePlatform.player.loadCount, 2);
    expect(fakePlatform.player.loadedUris.last, contains('id=3'));
  });

  test('natural end-of-track advances immediately, without the skip debounce', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    final tracks = [sampleTrack(id: '1'), sampleTrack(id: '2')];
    await service.play(tracks, from: 0);
    await waitUntil(() => !service.isLoading);
    expect(fakePlatform.player.loadCount, 1);

    fakePlatform.player.completeTrack();
    await waitUntil(() => fakePlatform.player.loadCount == 2);

    expect(service.currentTrack?.id, '2');
  });

  test('repeat-one reloads the same track on natural completion', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    service.toggleRepeatMode(); // all -> one
    final tracks = [sampleTrack(id: '1'), sampleTrack(id: '2')];
    await service.play(tracks, from: 0);
    await waitUntil(() => !service.isLoading);
    expect(fakePlatform.player.loadCount, 1);

    fakePlatform.player.completeTrack();
    await waitUntil(() => fakePlatform.player.loadCount == 2);

    expect(service.currentTrack?.id, '1'); // same track, reloaded
  });

  test('playShuffled enables shuffle and starts playback from the given tracks', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    final tracks = [sampleTrack(id: '1'), sampleTrack(id: '2'), sampleTrack(id: '3')];
    expect(service.isShuffleEnabled, isFalse);

    await service.playShuffled(tracks);
    await waitUntil(() => !service.isLoading);

    expect(service.isShuffleEnabled, isTrue);
    expect(tracks.map((t) => t.id), contains(service.currentTrack?.id));
    expect(fakePlatform.player.loadCount, 1);
  });

  test('playPrevious steps back through the playlist', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    final tracks = [sampleTrack(id: '1'), sampleTrack(id: '2'), sampleTrack(id: '3')];
    await service.play(tracks, from: 2);
    await waitUntil(() => !service.isLoading);

    await service.playPrevious();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await waitUntil(() => !service.isLoading);

    expect(service.currentTrack?.id, '2');
  });

  test('playNext plays the queue before continuing the playlist', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    final tracks = [sampleTrack(id: '1'), sampleTrack(id: '2')];
    await service.play(tracks, from: 0);
    await waitUntil(() => !service.isLoading);
    await service.addToQueue(sampleTrack(id: 'q'));

    await service.playNext();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await waitUntil(() => !service.isLoading);

    expect(service.currentTrack?.id, 'q');
    expect(service.queue, isEmpty);
    // The playlist cursor didn't move — Previous from here returns to the
    // interrupted playlist track (id '1'), not further back in the playlist.
    expect(service.currentIndex, 0);
  });

  test('stop clears playback and queue state', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    await service.playTrack(sampleTrack(id: '1'));
    await waitUntil(() => !service.isLoading);
    await service.addToQueue(sampleTrack(id: '2'));

    await service.stop();

    expect(service.currentTrack, isNull);
    expect(service.queue, isEmpty);
    expect(service.isPlaying, isFalse);
  });

  test('seek passes the position through to the platform', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    await service.playTrack(sampleTrack(id: '1'));
    await waitUntil(() => !service.isLoading);

    await service.seek(const Duration(seconds: 42));

    expect(fakePlatform.player.lastSeekPosition, const Duration(seconds: 42));
  });

  test('setVolume applies ReplayGain on top of the requested volume', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    await service.playTrack(sampleTrack(id: '1')); // no ReplayGain data -> factor 1.0
    await waitUntil(() => !service.isLoading);

    await service.setVolume(0.5);

    expect(fakePlatform.player.lastVolume, closeTo(0.5, 0.001));
  });

  test('togglePlayPause pauses then resumes', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    await service.playTrack(sampleTrack(id: '1'));
    await waitUntil(() => !service.isLoading);
    expect(service.isPlaying, isTrue);

    await service.togglePlayPause();
    expect(service.isPlaying, isFalse);

    await service.togglePlayPause();
    await waitUntil(() => service.isPlaying);
  });

  test('a load failure surfaces as lastError without crashing playback', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    final tracks = [sampleTrack(id: '1'), sampleTrack(id: '2')];
    await service.play(tracks, from: 0);
    await waitUntil(() => !service.isLoading);

    fakePlatform.player.failNextLoadWith = Exception('simulated stream-open failure');
    await service.playNext();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await waitUntil(() => !service.isLoading);

    expect(service.lastError, contains('Playback error'));
    expect(service.currentTrack?.id, '2'); // still shown, even though the load failed
  });

  test('recovers from a mid-stream drop by reloading the same track', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    await service.playTrack(sampleTrack(id: '1'));
    await waitUntil(() => !service.isLoading);
    expect(service.isPlaying, isTrue);

    fakePlatform.player.injectStreamError('stream drop');
    await waitUntil(() => !service.isLoading && fakePlatform.player.loadCount == 2);

    expect(service.currentTrack?.id, '1'); // recovered, still the same track
    expect(service.lastError, isNull);
  });

  test('gives up after 3 rapid drop-recovery attempts and surfaces the error', () async {
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());
    await service.playTrack(sampleTrack(id: '1'));
    await waitUntil(() => !service.isLoading);

    // Attempts 1-3 recover successfully (bounded to 3 rapid attempts).
    for (var i = 0; i < 3; i++) {
      fakePlatform.player.injectStreamError('drop $i');
      await waitUntil(() => !service.isLoading);
    }
    expect(service.lastError, isNull);

    // A 4th rapid drop exceeds the bound and is treated as unrecoverable.
    fakePlatform.player.injectStreamError('drop 4');
    await waitUntil(() => service.lastError != null);

    expect(service.lastError, contains('Playback error'));
  });

  test('drop recovery runs the same load path as a fresh selection, not a partial copy', () async {
    // Regression: recovery used to re-implement the load sequence by hand and
    // skip presence.show() (and _logStreamParams, cache eviction) in the
    // process. A second `show` call after recovery proves the recovery path
    // now goes through the same _loadAndPlay as a fresh track.
    final presence = RecordingPresence();
    final service = AudioPlayerService(presence: presence, resolver: const FakeStreamUrlResolver());
    await service.playTrack(sampleTrack(id: '1'));
    await waitUntil(() => !service.isLoading);
    expect(presence.shown, hasLength(1));

    fakePlatform.player.injectStreamError('stream drop');
    await waitUntil(() => !service.isLoading && fakePlatform.player.loadCount == 2);

    expect(presence.shown, hasLength(2));
  });

  test('bind wires the live player and transport commands once, at first playback', () async {
    final presence = RecordingPresence();
    final service = AudioPlayerService(presence: presence, resolver: const FakeStreamUrlResolver());
    expect(presence.boundPlayer, isNull);

    await service.playTrack(sampleTrack(id: '1'));
    await waitUntil(() => !service.isLoading);

    expect(presence.boundPlayer, isNotNull);
    expect(presence.boundCommands, isNotNull);
  });

  test('setPlaying reports state changes only while a track is current', () async {
    final presence = RecordingPresence();
    final service = AudioPlayerService(presence: presence, resolver: const FakeStreamUrlResolver());

    await service.playTrack(sampleTrack(id: '1'));
    await waitUntil(() => !service.isLoading);
    expect(presence.playingStates, isNotEmpty);
    expect(presence.playingStates.last, isTrue);

    await service.stop();

    expect(presence.clearCount, 1);
  });
}
