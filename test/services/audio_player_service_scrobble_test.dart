import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import '../support/fake_just_audio.dart';
import '../support/fake_reporter.dart';
import '../support/fake_resolver.dart';
import '../support/fixtures.dart';

// Covers what AudioPlayerService reports back to the server: the "now playing"
// announcement when a track starts, and the scrobble once playback passes the
// threshold (half the track, or four minutes, whichever is first).
//
// The fake platform reports a 3-minute duration, so the threshold is 90s —
// crossed here with FakeAudioPlayerPlatform.reportPosition rather than by
// waiting. See audio_player_service_playback_test.dart for the playback
// entry points these ride on, and docs/decisions.md for why the rule is
// position-based rather than accumulated listening time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Same audio_session stub as the playback tests — just_audio activates an OS
  // audio session on every play(), which is a MissingPluginException here.
  const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  late FakeJustAudioPlatform fakePlatform;
  late RecordingReporter reporter;

  setUp(() {
    fakePlatform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = fakePlatform;
    reporter = RecordingReporter();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, null);
  });

  AudioPlayerService buildService() => AudioPlayerService(
    resolver: const FakeStreamUrlResolver(),
    reporter: reporter,
  );

  /// Polls until [test] passes. Same shape (and same reason) as the helper in
  /// audio_player_service_playback_test.dart: reports reach the reporter
  /// through the position stream and an unawaited future, so there is no one
  /// future a test can await instead.
  Future<void> waitUntil(
    bool Function() test, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    do {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (test()) return;
    } while (DateTime.now().isBefore(deadline));
    fail('Condition not met within $timeout');
  }

  test('starting a track announces it as now playing', () async {
    final service = buildService();
    await service.playTrack(sampleTrack(id: 'song-1'));

    await waitUntil(() => reporter.nowPlayingIds.isNotEmpty);
    expect(reporter.nowPlayingIds, ['song-1']);
    // Announcing is not a play count — nothing scrobbled yet.
    expect(reporter.scrobbles, isEmpty);

    service.dispose();
  });

  test('playing past the halfway threshold scrobbles once', () async {
    final service = buildService();
    final before = DateTime.now();
    await service.playTrack(sampleTrack(id: 'song-1'));
    await waitUntil(() => fakePlatform.player.loadCount == 1);

    // 3-minute track → 90s threshold.
    fakePlatform.player.reportPosition(const Duration(seconds: 95));

    await waitUntil(() => reporter.scrobbles.isNotEmpty);
    expect(reporter.scrobbledIds, ['song-1']);
    // Timed from when the listen began, not when the threshold was crossed:
    // the stamp falls between "just before playTrack" and now.
    final startedAt = reporter.scrobbles.single.startedAt;
    expect(startedAt, isNotNull);
    expect(startedAt!.isBefore(before), isFalse);
    expect(startedAt.isAfter(DateTime.now()), isFalse);

    service.dispose();
  });

  test('stopping short of the threshold does not scrobble', () async {
    final service = buildService();
    await service.playTrack(sampleTrack(id: 'song-1'));
    await waitUntil(() => fakePlatform.player.loadCount == 1);

    fakePlatform.player.reportPosition(const Duration(seconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(reporter.scrobbles, isEmpty);

    service.dispose();
  });

  test('crossing the threshold repeatedly still scrobbles only once', () async {
    final service = buildService();
    await service.playTrack(sampleTrack(id: 'song-1'));
    await waitUntil(() => fakePlatform.player.loadCount == 1);

    fakePlatform.player.reportPosition(const Duration(seconds: 95));
    await waitUntil(() => reporter.scrobbles.isNotEmpty);
    fakePlatform.player.reportPosition(const Duration(seconds: 120));
    fakePlatform.player.reportPosition(const Duration(seconds: 150));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(reporter.scrobbledIds, ['song-1']);

    service.dispose();
  });

  test('replaying the same track scrobbles it again', () async {
    final service = buildService();
    final track = sampleTrack(id: 'song-1');

    await service.playTrack(track);
    await waitUntil(() => fakePlatform.player.loadCount == 1);
    fakePlatform.player.reportPosition(const Duration(seconds: 95));
    await waitUntil(() => reporter.scrobbles.length == 1);

    // A fresh selection is a new listen, so it counts again.
    await service.playTrack(track);
    await waitUntil(() => fakePlatform.player.loadCount == 2);
    fakePlatform.player.reportPosition(const Duration(seconds: 95));
    await waitUntil(() => reporter.scrobbles.length == 2);

    expect(reporter.scrobbledIds, ['song-1', 'song-1']);

    service.dispose();
  });

  test('a mid-stream drop and resume stays one listen', () async {
    final service = buildService();
    await service.playTrack(sampleTrack(id: 'song-1'));
    await waitUntil(() => fakePlatform.player.loadCount == 1);

    fakePlatform.player.reportPosition(const Duration(seconds: 95));
    await waitUntil(() => reporter.scrobbles.isNotEmpty);

    // Drop recovery re-opens the track without going through a fresh
    // selection — the same listen continues, so it must not count twice.
    fakePlatform.player.injectStreamError('connection closed');
    await waitUntil(() => fakePlatform.player.loadCount == 2);
    fakePlatform.player.reportPosition(const Duration(seconds: 150));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(reporter.scrobbledIds, ['song-1']);

    service.dispose();
  });

  test('a failing reporter never surfaces as a playback error', () async {
    reporter.failWith = StateError('server said no');
    final service = buildService();

    await service.playTrack(sampleTrack(id: 'song-1'));
    await waitUntil(() => fakePlatform.player.loadCount == 1);
    fakePlatform.player.reportPosition(const Duration(seconds: 95));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(service.lastError, isNull);
    expect(service.currentTrack?.id, 'song-1');

    service.dispose();
  });

  test('no reporter configured is a safe default', () async {
    // AudioPlayerService()'s default is NoPlaybackReporter — unlike the URL
    // resolver, a missing reporter must not throw.
    final service = AudioPlayerService(resolver: const FakeStreamUrlResolver());

    await service.playTrack(sampleTrack(id: 'song-1'));
    await waitUntil(() => fakePlatform.player.loadCount == 1);
    fakePlatform.player.reportPosition(const Duration(seconds: 95));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(service.lastError, isNull);

    service.dispose();
  });
}
