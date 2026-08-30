import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/audio_player_service.dart';

/// How far the arrow keys move. Ten seconds is the near-universal convention
/// for a media player; 5% gives volume twenty steps end to end, which is fine
/// enough to be useful and coarse enough to cross the range quickly.
const _seekStep = Duration(seconds: 10);
const _volumeStep = 0.05;

/// Window-level playback keyboard shortcuts for the desktop layouts.
///
/// | Key | Action |
/// |---|---|
/// | Space | Play / pause |
/// | ← / → | Seek back / forward 10s |
/// | Ctrl + ← / → | Previous / next track |
/// | ↑ / ↓ | Volume up / down |
/// | Escape | Close Now Playing (only where [onEscape] is given) |
///
/// Wrapped around *both* desktop roots — [DesktopShell] and
/// [DesktopPlayerScreen] — because Now Playing is pushed on the root
/// navigator and so is not inside the shell's subtree. Anything relying on the
/// shell alone would leave the player screen, the one place a user is most
/// likely to reach for these keys, without them.
///
/// Media keys are a separate path and already work without this (MPRIS on
/// Linux, SMTC on Windows — see [NowPlayingPresence]); those are system-wide,
/// this is in-window.
class DesktopPlaybackShortcuts extends StatelessWidget {
  final Widget child;

  /// What Escape does here, if anything. Null on the shell — there is nothing
  /// to back out of — and "close the player" on Now Playing.
  final VoidCallback? onEscape;

  const DesktopPlaybackShortcuts({
    super.key,
    required this.child,
    this.onEscape,
  });

  /// True while a text field owns the keyboard.
  ///
  /// These bindings sit above the whole window, so without this a space typed
  /// into the search box would toggle playback instead of typing. Arrow keys
  /// are consumed by [EditableText]'s own (closer) handlers before reaching
  /// here, but the guard covers them too rather than depending on that
  /// ordering.
  static bool get _isTyping {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Run [action] against the player, unless the user is typing.
  static void _play(
    BuildContext context,
    void Function(AudioPlayerService) action,
  ) {
    if (_isTyping) return;
    action(context.read<AudioPlayerService>());
  }

  static void _seekBy(AudioPlayerService player, Duration delta) {
    final position = player.position;
    if (position == null || player.currentTrack == null) return;
    var target = position + delta;
    if (target < Duration.zero) target = Duration.zero;
    final duration = player.duration;
    if (duration != null && target > duration) target = duration;
    player.seek(target);
  }

  static void _nudgeVolume(AudioPlayerService player, double delta) {
    player.setVolume((player.volume + delta).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _play(context, (p) => p.togglePlayPause()),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _play(context, (p) => _seekBy(p, -_seekStep)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _play(context, (p) => _seekBy(p, _seekStep)),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
        ): () =>
            _play(context, (p) => p.playPrevious()),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
        ): () =>
            _play(context, (p) => p.playNext()),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _play(context, (p) => _nudgeVolume(p, _volumeStep)),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _play(context, (p) => _nudgeVolume(p, -_volumeStep)),
        if (onEscape case final onEscape?)
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_isTyping) onEscape();
          },
      },
      // Key events reach a CallbackShortcuts only by bubbling up from the
      // focused node. The enclosing route's FocusScope sits *above* this
      // widget, so with nothing focused inside, nothing would bubble through
      // here at all and the shortcuts would be dead until the user clicked
      // something. This node gives the subtree a focus holder from first
      // frame.
      //
      // Caveat if you add to a desktop screen later: this claims autofocus,
      // so a descendant that also asks for it (an autofocusing search or
      // login field) will not reliably win. No desktop screen autofocuses
      // today. skipTraversal keeps the holder out of the Tab order, where it
      // would otherwise be a stop that does nothing.
      child: Focus(autofocus: true, skipTraversal: true, child: child),
    );
  }
}
