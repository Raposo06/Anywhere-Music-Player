import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/audio_player_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// The small shared pieces the desktop screens all build out of. They exist
/// here rather than in each screen because the design reuses them verbatim —
/// the same uppercase section label heads "Albums", "Tracks" and "Up Next";
/// the same three-bar glyph marks the playing row in both the track list and
/// the queue panel.

/// Uppercase 11px section heading — "ALBUMS", "TRACKS", "UP NEXT".
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.06 * 11,
        color: AppColors.faint,
      ),
    );
  }
}

/// A row that lightens to [AppColors.surface2] under the pointer.
///
/// The mock shows only the resting state; the handoff asks for this hover
/// separately ("expected for desktop pointer input"). Material's [InkWell]
/// would give a ripple the design doesn't have, so this is a plain
/// colour swap on the same fast transition as everything else.
class HoverRow extends StatefulWidget {
  /// The row's content, when it doesn't care about hover. Exactly one of this
  /// and [builder] must be given.
  final Widget? child;

  /// The row's content, built with the current hover state — for content that
  /// changes on hover, like the favourite heart that stays hidden until the
  /// pointer is over the row.
  final Widget Function(bool hovered)? builder;

  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;

  /// Overrides the resting background — the playing row passes
  /// [AppColors.accentSoft] so hover doesn't wash out its highlight.
  final Color? background;

  const HoverRow({
    super.key,
    this.child,
    this.builder,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    this.radius = 8,
    this.background,
  }) : assert(
         (child == null) != (builder == null),
         'give exactly one of child or builder',
       );

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final resting = widget.background ?? Colors.transparent;
    // On an already-highlighted row, hover deepens the accent fill instead of
    // replacing it with the neutral grey (which would read as *less* selected).
    final hovered = widget.background != null
        ? Color.alphaBlend(AppColors.accentSoft, resting)
        : AppColors.surface2;

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMetrics.stateTransition,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered && widget.onTap != null ? hovered : resting,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: widget.child ?? widget.builder!(_hovered),
        ),
      ),
    );
  }
}

/// The three-bar "this one is playing" glyph.
///
/// Animates only while playback is actually running — a frozen glyph on a
/// paused track is the useful distinction, and it also keeps the ticker off
/// the moment nothing is moving.
class PlayingBars extends StatefulWidget {
  final double size;
  final Color color;

  const PlayingBars({super.key, this.size = 14, this.color = AppColors.accent});

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.read<AudioPlayerService>();

    return StreamBuilder<bool>(
      stream: playerService.playingStream,
      initialData: playerService.isPlaying,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;
        // Deferred to after the frame on purpose. Starting or stopping the
        // controller notifies its listeners synchronously, and the
        // AnimatedBuilder below is already one of them on every rebuild after
        // the first — doing it inline would call markNeedsBuild mid-build.
        if (isPlaying != _controller.isAnimating) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (isPlaying) {
              _controller.repeat();
            } else {
              _controller.stop();
            }
          });
        }

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _BarsPainter(
                phase: _controller.value,
                color: widget.color,
                // Held still when paused, at the mock's resting heights.
                animate: isPlaying,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  final double phase;
  final Color color;
  final bool animate;

  /// Resting heights, as fractions of the glyph box — the proportions the
  /// static mock draws (short, tall, shortest).
  static const _resting = [0.44, 0.72, 0.28];

  const _BarsPainter({
    required this.phase,
    required this.color,
    required this.animate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const barCount = 3;
    final barWidth = size.width * 0.19;
    final gap = (size.width - barCount * barWidth) / (barCount - 1);

    for (var i = 0; i < barCount; i++) {
      final double fraction;
      if (animate) {
        // Each bar runs the same wave a third of a cycle apart, so they
        // never all peak together.
        final t = (phase + i / barCount) * 2 * math.pi;
        fraction = 0.28 + 0.62 * (0.5 + 0.5 * math.sin(t));
      } else {
        fraction = _resting[i];
      }
      final height = size.height * fraction;
      final left = i * (barWidth + gap);
      canvas.drawRect(
        Rect.fromLTWH(left, size.height - height, barWidth, height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.animate != animate;
}

/// The round accent play/pause button — the design's one truly emphatic
/// control. Used at 60px on Now Playing, 38px in the mini player and 38px
/// over folder cards.
class AccentCircleButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// The full accent glow sits under the 60px Now Playing button; the smaller
  /// instances get a tighter shadow so they don't bloom over neighbouring rows.
  final bool glow;

  const AccentCircleButton({
    super.key,
    required this.size,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        hoverColor: AppColors.accentStrong,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.42, color: Colors.white),
        ),
      ),
    );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: glow
            ? AppShadows.accentGlow
            : const [
                BoxShadow(
                  color: AppColors.accentGlow,
                  blurRadius: 7,
                  spreadRadius: -1,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: button,
    );

    if (tooltip == null) return decorated;
    return Tooltip(message: tooltip!, child: decorated);
  }
}

/// A flat, muted transport glyph (skip back / skip forward).
///
/// The handoff is explicit that these are the plain filled triangle-and-bar
/// shapes, which is exactly what Material's `skip_previous`/`skip_next` draw —
/// so this is only about sizing and the muted/disabled colouring.
class TransportButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;
  final String tooltip;
  final FocusNode? focusNode;

  const TransportButton({
    super.key,
    required this.icon,
    required this.size,
    required this.onPressed,
    required this.tooltip,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      focusNode: focusNode,
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: size,
      color: AppColors.muted,
      disabledColor: AppColors.faint,
      hoverColor: AppColors.surface2,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tight(Size.square(size + 12)),
    );
  }
}

/// Formats a duration as `mm:ss` (or `h:mm:ss` past an hour) — the format the
/// design shows for both track durations and the scrub bar's time labels.
String formatPlaybackDuration(Duration? d) {
  if (d == null) return '00:00';
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }
  return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
}

/// The serif style used for anything that is a *name* — track titles, folder
/// names, screen headings.
TextStyle serifStyle({
  required double fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
}) {
  return TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );
}
