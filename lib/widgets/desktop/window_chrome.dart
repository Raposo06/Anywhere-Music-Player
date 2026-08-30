import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/platform_detector.dart';

/// The app's name as shown to a person — in the title bar and the taskbar.
///
/// Deliberately not the package name (`anywhere_music_player`): the window
/// chrome is user-facing copy, and this matches `MaterialApp.title`.
const appDisplayName = 'Anywhere Music Player';

/// Adds the app-drawn title bar above [child] on desktop; elsewhere returns
/// [child] untouched.
///
/// For the screens that live *outside* [DesktopShell] — the auth loading state
/// and the login screen. `main()` hides the native frame before the first
/// frame, so without this those screens would leave the user unable to move or
/// close the window.
class DesktopWindowFrame extends StatelessWidget {
  final Widget child;

  const DesktopWindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetector.isDesktop) return child;
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          const WindowChrome(label: appDisplayName),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The app-drawn title bar that replaces the OS window frame on desktop, at
/// [AppMetrics.titlebarHeight].
///
/// `main()` hides the native frame (`TitleBarStyle.hidden`) on desktop, so
/// this bar is the *only* way to move, maximise or close the window — every
/// screen inside the desktop shell must render one. It carries the app
/// identity on the left, an optional back affordance (Now Playing uses it),
/// and the three window controls on the right.
///
/// The window title is still set natively by `WindowsPresence` for the
/// taskbar; [label] is the separate, in-frame copy of that context, since a
/// hidden frame has nowhere to show the native one.
class WindowChrome extends StatelessWidget {
  /// The muted context line, e.g. `Bleach — Anywhere Music Player`.
  final String label;

  /// Shown in place of the app icon when set — a back chevron, as on the
  /// Now Playing screen.
  final VoidCallback? onBack;

  const WindowChrome({super.key, required this.label, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppMetrics.titlebarHeight,
      child: ColoredBox(
        color: AppColors.titlebar,
        child: Row(
          children: [
            // The draggable region. Everything not a button belongs to it,
            // so the user can grab the bar anywhere in the gap between the
            // label and the window controls.
            Expanded(
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      if (onBack case final back?)
                        _ChromeIconButton(
                          onPressed: back,
                          tooltip: 'Back (Esc)',
                          // Same width as the window controls — it used to be
                          // narrower for no reason tied to how often it gets
                          // clicked. See docs/decisions.md.
                          child: const Icon(
                            Icons.chevron_left,
                            size: 26,
                            color: AppColors.muted,
                          ),
                        )
                      else
                        const _AppGlyph(),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.faint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const _WindowControls(),
          ],
        ),
      ),
    );
  }
}

/// The rounded accent square with a white music-note glyph — the app mark
/// from the design, drawn rather than shipped as an asset so it picks up the
/// accent colour. Scaled up from the design's original 20px alongside the
/// rest of the bar — see [AppMetrics.titlebarHeight].
class _AppGlyph extends StatelessWidget {
  const _AppGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.music_note, size: 17, color: Colors.white),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ChromeIconButton(
          onPressed: windowManager.minimize,
          tooltip: 'Minimise',
          child: const _GlyphMinimise(),
        ),
        _ChromeIconButton(
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          tooltip: 'Maximise',
          child: const _GlyphMaximise(),
        ),
        _ChromeIconButton(
          onPressed: windowManager.close,
          tooltip: 'Close',
          hoverColor: AppColors.destructive,
          child: const _GlyphClose(),
        ),
      ],
    );
  }
}

/// A full-height, 50px-wide hit target in the chrome. Close uses [hoverColor]
/// to go red; the others lighten to [AppColors.surface2].
class _ChromeIconButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final Widget child;
  final Color hoverColor;

  const _ChromeIconButton({
    required this.onPressed,
    required this.tooltip,
    required this.child,
    this.hoverColor = AppColors.surface2,
  });

  @override
  State<_ChromeIconButton> createState() => _ChromeIconButtonState();
}

class _ChromeIconButtonState extends State<_ChromeIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: pointerCursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: AppMetrics.stateTransition,
            width: 50,
            height: AppMetrics.titlebarHeight,
            alignment: Alignment.center,
            color: _hovered ? widget.hoverColor : Colors.transparent,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// The three control glyphs. Material's own icons are too heavy and too
// rounded next to a thin line, so these are drawn to the design's stroke
// weights — scaled up from the design's original 10px alongside the rest of
// the bar, see [AppMetrics.titlebarHeight].

class _GlyphMinimise extends StatelessWidget {
  const _GlyphMinimise();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 13,
    height: 1.6,
    child: ColoredBox(color: AppColors.muted),
  );
}

class _GlyphMaximise extends StatelessWidget {
  const _GlyphMaximise();

  @override
  Widget build(BuildContext context) => Container(
    width: 13,
    height: 13,
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.muted, width: 1.4),
    ),
  );
}

class _GlyphClose extends StatelessWidget {
  const _GlyphClose();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 13,
    height: 13,
    child: CustomPaint(painter: _ClosePainter()),
  );
}

class _ClosePainter extends CustomPainter {
  const _ClosePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.muted
      ..strokeWidth = 1.6
      ..isAntiAlias = true;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_ClosePainter oldDelegate) => false;
}
