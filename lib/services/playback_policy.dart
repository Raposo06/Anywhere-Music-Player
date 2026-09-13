import 'dart:math' show pow;

/// The tuning knobs of playback, as pure functions.
///
/// These are the decisions with no dependency on a live audio backend: what
/// counts as a listen, how loud a track plays. They lived inside [AudioPlayerService], where reaching one
/// from a test meant either constructing a real `AudioPlayer` or drilling a
/// `@visibleForTesting` hole through the class. Same shape as
/// `PlaybackCursor`: pure Dart, no Flutter, no just_audio, tested directly.
///
/// Deliberately *not* here: mid-stream drop recovery. It reads like a policy
/// ("3 attempts, 30-second window") but it is three mutable fields and a call
/// to `DateTime.now()`, so moving it would mean inventing a clock seam — and
/// it sits on top of "never auto-resume while paused" (CLAUDE.md item 7),
/// which is only really verifiable on a device.
abstract final class PlaybackPolicy {
  // -------- Scrobbling --------

  /// Report a play once it passes the Last.fm-style threshold: half the
  /// track, or [_scrobbleAfter], whichever comes first.
  static const double _scrobbleFraction = 0.5;
  static const Duration _scrobbleAfter = Duration(minutes: 4);

  /// How far into a track of length [total] a listen becomes a scrobble.
  static Duration scrobbleThreshold(Duration total) {
    final fraction = Duration(
      microseconds: (total.inMicroseconds * _scrobbleFraction).round(),
    );
    return fraction < _scrobbleAfter ? fraction : _scrobbleAfter;
  }

  // -------- ReplayGain --------

  /// ReplayGain pre-amp in dB. Middle-ground value picked to balance two
  /// competing goals:
  ///
  ///   • Equal loudness across tracks (low values → loud masters fully
  ///     attenuated to the ReplayGain reference)
  ///   • Acceptable overall volume (high values → less attenuation, library
  ///     plays louder, but the variance between tracks widens)
  ///
  /// Reference table for a track with rgTrackGain = -7 dB (typical pop
  /// master), since clamp(0..1) caps amplification at unity:
  ///   preamp 0 → factor 0.45  (-7 dB attenuation, full normalization)
  ///   preamp 3 → factor 0.63  (-4 dB attenuation)
  ///   preamp 6 → factor 0.89  (-1 dB attenuation, current setting — plays
  ///                            louder, near the file's own level)
  ///   preamp 9 → factor 1.00  (no attenuation; loudest, leveling effectively
  ///                            off — bump here if you want it louder still)
  static const double _replayGainPreAmpDb = 6.0;

  /// Linear playback multiplier for a track whose ReplayGain is [db].
  ///
  /// **Attenuate-only** (CLAUDE.md item 3): after the pre-amp, tracks still
  /// louder than the target are turned down toward it; quieter tracks are
  /// never boosted. The `clamp` is what makes clipping impossible — the
  /// pre-amp is the tuning knob, the clamp is not. A null [db] (no loudness
  /// data) plays unchanged.
  static double replayGainFactor(double? db) {
    if (db == null) return 1.0;
    final factor = pow(10, (db + _replayGainPreAmpDb) / 20).toDouble();
    return factor.clamp(0.0, 1.0).toDouble();
  }
}
