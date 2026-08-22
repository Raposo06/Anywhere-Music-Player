import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/models/track.dart';

// Covers the ReplayGain factor math documented in docs/decisions.md — an
// attenuate-only curve with a +6 dB pre-amp, clamped to [0, 1] so clipping is
// impossible by construction. See AudioPlayerService._replayGainFactor.
void main() {
  final service = AudioPlayerService();

  Track trackWithGain(double? db) => Track(
    id: '1',
    title: 'T',
    filename: 'f.mp3',
    streamUrl: 'https://x/stream',
    folderPath: '',
    createdAt: DateTime(2024),
    replayGainDb: db,
  );

  test('plays unchanged (factor 1.0) when the track has no ReplayGain data', () {
    expect(service.replayGainFactorForTest(null), 1.0);
    expect(service.replayGainFactorForTest(trackWithGain(null)), 1.0);
  });

  test('matches the documented reference table for a -7 dB pop master', () {
    // preamp 6 → factor 0.89 (-1 dB attenuation) per docs/decisions.md.
    final factor = service.replayGainFactorForTest(trackWithGain(-7.0));
    expect(factor, closeTo(0.89, 0.01));
  });

  test('never boosts a quiet track above unity (clamp prevents clipping)', () {
    // A track already louder than the reference (positive rgTrackGain) would
    // compute a factor > 1 without the clamp.
    final factor = service.replayGainFactorForTest(trackWithGain(10.0));
    expect(factor, 1.0);
  });

  test('attenuates a loud track toward the reference level', () {
    // A very loud master (large negative rgTrackGain) should be turned down
    // significantly, but never below 0.
    final factor = service.replayGainFactorForTest(trackWithGain(-20.0));
    expect(factor, greaterThan(0.0));
    expect(factor, lessThan(0.2));
  });

  test('is monotonically non-decreasing as the track gets louder (less negative dB)', () {
    final quiet = service.replayGainFactorForTest(trackWithGain(-15.0));
    final medium = service.replayGainFactorForTest(trackWithGain(-8.0));
    final loud = service.replayGainFactorForTest(trackWithGain(-2.0));

    expect(quiet, lessThanOrEqualTo(medium));
    expect(medium, lessThanOrEqualTo(loud));
  });
}
