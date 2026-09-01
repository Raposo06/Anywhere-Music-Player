import 'package:flutter/material.dart';

/// Formats a duration as `mm:ss` (or `h:mm:ss` past an hour) — the form the
/// players show for the scrub bar's elapsed / total labels.
String formatPlaybackDuration(Duration? d) {
  if (d == null) return '00:00';
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${two(d.inMinutes.remainder(60))}:'
        '${two(d.inSeconds.remainder(60))}';
  }
  return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
}

/// One frame of scrub-bar state, handed to [ScrubBar.builder].
typedef ScrubBarView = ({
  /// 0..1, clamped — wire straight to `Slider.value`.
  double fraction,

  /// Elapsed time for the left label: the drag target while the user is
  /// dragging, the live playback position otherwise.
  Duration position,

  /// Wire straight to the matching `Slider` callbacks. All three are null when
  /// the bar is read-only ([ScrubBar.onSeek] is null) or the track length is
  /// unknown — a `Slider` with null `onChanged` renders disabled.
  ValueChanged<double>? onChangeStart,
  ValueChanged<double>? onChanged,
  ValueChanged<double>? onChangeEnd,
});

/// The elapsed / total position bar under the player art.
///
/// Owns the one part that was genuinely fiddly and had been written out three
/// times (phone, desktop, TV): while the user drags the thumb the bar follows
/// the finger — not the position stream — and on release it seeks, *unless* the
/// track auto-advanced mid-drag, in which case the seek is dropped. Everything
/// visible — the `Slider`'s theme, the label text styles, the column spacing —
/// stays with the caller, via [builder].
///
/// Seeking works on every platform (Android plays from a seekable cache file),
/// so the only gate is whether the track's length is known. Pass a null
/// [onSeek] for a display-only bar (the TV remote has no scrub gesture).
class ScrubBar extends StatefulWidget {
  /// Length of the current track. `Duration.zero` (unknown) pins the bar at the
  /// start and disables seeking.
  final Duration duration;

  /// Identifies the current track, so a mid-drag auto-advance can be spotted
  /// and its seek discarded. Irrelevant when [onSeek] is null.
  final String? trackId;

  /// High-frequency playback position.
  final Stream<Duration> position;

  /// Called on release with the absolute position to seek to, when the track
  /// has not changed since the drag began. Null for a display-only bar.
  final ValueChanged<Duration>? onSeek;

  /// Builds the visible bar from the current [ScrubBarView].
  final Widget Function(BuildContext context, ScrubBarView view) builder;

  const ScrubBar({
    super.key,
    required this.duration,
    required this.trackId,
    required this.position,
    required this.onSeek,
    required this.builder,
  });

  @override
  State<ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<ScrubBar> {
  // While true, the bar and its label follow [_dragValue] (a 0..1 fraction)
  // instead of the position stream, keeping the thumb glued to the pointer.
  // [_dragStartTrackId] is captured at drag start so the seek is discarded if
  // the track auto-advanced before release.
  bool _isDragging = false;
  double _dragValue = 0;
  String? _dragStartTrackId;

  bool get _canSeek =>
      widget.onSeek != null && widget.duration > Duration.zero;

  void _onChangeStart(double value) {
    setState(() {
      _isDragging = true;
      _dragValue = value;
      _dragStartTrackId = widget.trackId;
    });
  }

  void _onChanged(double value) => setState(() => _dragValue = value);

  void _onChangeEnd(double value) {
    final sameTrack = widget.trackId == _dragStartTrackId;
    setState(() {
      _isDragging = false;
      _dragStartTrackId = null;
    });
    if (sameTrack && _canSeek) {
      widget.onSeek!(
        Duration(
          milliseconds: (value * widget.duration.inMilliseconds).round(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDuration = widget.duration > Duration.zero;

    return StreamBuilder<Duration>(
      stream: widget.position,
      builder: (context, snapshot) {
        final streamPosition = snapshot.data ?? Duration.zero;
        final fraction = _isDragging
            ? _dragValue
            : (hasDuration
                ? streamPosition.inMilliseconds /
                    widget.duration.inMilliseconds
                : 0.0);
        final position = _isDragging
            ? Duration(
                milliseconds:
                    (_dragValue * widget.duration.inMilliseconds).round())
            : streamPosition;

        return widget.builder(context, (
          fraction: fraction.clamp(0.0, 1.0),
          position: position,
          onChangeStart: _canSeek ? _onChangeStart : null,
          onChanged: _canSeek ? _onChanged : null,
          onChangeEnd: _canSeek ? _onChangeEnd : null,
        ));
      },
    );
  }
}
