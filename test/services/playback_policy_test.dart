import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/services/playback_policy.dart';

// These used to reach into AudioPlayerService through a @visibleForTesting
// wrapper, and had to construct a real service to do it. The policies are
// pure, so this file constructs nothing.
void main() {
  group('replayGainFactor', () {
    test('plays unchanged (factor 1.0) when the track has no ReplayGain data', () {
      expect(PlaybackPolicy.replayGainFactor(null), 1.0);
    });

    test('matches the documented reference table for a -7 dB pop master', () {
      // preamp 6 → factor 0.89 (-1 dB attenuation) per docs/decisions.md.
      expect(PlaybackPolicy.replayGainFactor(-7.0), closeTo(0.89, 0.01));
    });

    test('never boosts a quiet track above unity (clamp prevents clipping)', () {
      // A track already louder than the reference (positive rgTrackGain) would
      // compute a factor > 1 without the clamp.
      expect(PlaybackPolicy.replayGainFactor(10.0), 1.0);
      // The clamp, not the pre-amp, is what makes this impossible — CLAUDE.md
      // item 3. Anything at or above -6 dB is already at unity.
      expect(PlaybackPolicy.replayGainFactor(-6.0), 1.0);
      expect(PlaybackPolicy.replayGainFactor(0.0), 1.0);
    });

    test('attenuates a loud track toward the reference level', () {
      // A very loud master (large negative rgTrackGain) should be turned down
      // significantly, but never below 0.
      final factor = PlaybackPolicy.replayGainFactor(-20.0);
      expect(factor, greaterThan(0.0));
      expect(factor, lessThan(0.2));
    });

    test('is monotonically non-decreasing as the track gets louder', () {
      final quiet = PlaybackPolicy.replayGainFactor(-15.0);
      final medium = PlaybackPolicy.replayGainFactor(-8.0);
      final loud = PlaybackPolicy.replayGainFactor(-2.0);

      expect(quiet, lessThanOrEqualTo(medium));
      expect(medium, lessThanOrEqualTo(loud));
    });
  });

  group('scrobbleThreshold', () {
    test('is half of a short track', () {
      expect(
        PlaybackPolicy.scrobbleThreshold(const Duration(minutes: 3)),
        const Duration(seconds: 90),
      );
    });

    test('caps at four minutes once half the track is longer than that', () {
      // The crossover is an 8-minute track; a 90-minute mix scrobbles at the
      // same 4 minutes, not at 45.
      expect(
        PlaybackPolicy.scrobbleThreshold(const Duration(minutes: 8)),
        const Duration(minutes: 4),
      );
      expect(
        PlaybackPolicy.scrobbleThreshold(const Duration(minutes: 90)),
        const Duration(minutes: 4),
      );
    });

    test('a zero-length track needs no listening at all', () {
      expect(PlaybackPolicy.scrobbleThreshold(Duration.zero), Duration.zero);
    });
  });
}
