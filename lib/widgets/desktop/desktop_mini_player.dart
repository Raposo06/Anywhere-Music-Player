// `RepeatMode` collides with Flutter's own (unrelated) animation-builder
// symbol added in 3.47 — hide it so this app's enum resolves. See
// docs/operations.md.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../theme/app_colors.dart';
import '../cover_art.dart';
import 'desktop_primitives.dart';
import '../favourite_button.dart';

/// The persistent playback bar docked at the bottom of the desktop shell.
///
/// Shown on every desktop screen except Now Playing; clicking anywhere that
/// isn't a control opens the full player. Collapses to nothing when there is
/// no current track, so the shell doesn't reserve space for an empty bar.
class DesktopMiniPlayer extends StatelessWidget {
  final VoidCallback onOpenPlayer;

  const DesktopMiniPlayer({super.key, required this.onOpenPlayer});

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, Track?>(
      selector: (_, ps) => ps.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return _Bar(track: track, onOpenPlayer: onOpenPlayer);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final Track track;
  final VoidCallback onOpenPlayer;

  const _Bar({required this.track, required this.onOpenPlayer});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.miniPlayer,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _ProgressStrip(),
          SizedBox(
            // The strip sits above the row, so the row itself is the bar
            // height less the strip.
            height: AppMetrics.miniPlayerHeight - 3,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onOpenPlayer,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      CoverArt(
                        track,
                        size: 44,
                        radius: 8,
                        showPlaceholder: false,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: serifStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                            if (track.artist case final artist?
                                when artist.trim().isNotEmpty)
                              Text(
                                artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      FavouriteButton(track: track, size: 17),
                      const SizedBox(width: 4),
                      // The controls sit inside the same tap target as the
                      // bar, so they have to swallow their own clicks —
                      // IconButton/InkWell already do, which is why the row
                      // click above can stay a plain GestureDetector.
                      const _Controls(),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.keyboard_arrow_up,
                        size: 18,
                        color: AppColors.faint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 3px accent progress strip across the top of the bar.
class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip();

  @override
  Widget build(BuildContext context) {
    final playerService = context.read<AudioPlayerService>();
    return StreamBuilder<Duration>(
      stream: playerService.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = playerService.duration ?? Duration.zero;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;
        return LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 3,
          backgroundColor: AppColors.surface2,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final playerService = context.read<AudioPlayerService>();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _ShuffleToggle(),
        TransportButton(
          icon: Icons.skip_previous,
          size: 18,
          tooltip: 'Previous (Ctrl+←)',
          onPressed: playerService.playPrevious,
        ),
        StreamBuilder<bool>(
          stream: playerService.playingStream,
          initialData: playerService.isPlaying,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return AccentCircleButton(
              size: 38,
              icon: isPlaying ? Icons.pause : Icons.play_arrow,
              tooltip: isPlaying ? 'Pause (Space)' : 'Play (Space)',
              onPressed: playerService.togglePlayPause,
            );
          },
        ),
        TransportButton(
          icon: Icons.skip_next,
          size: 18,
          tooltip: 'Next (Ctrl+→)',
          onPressed: playerService.playNext,
        ),
        const _RepeatToggle(),
      ],
    );
  }
}

/// Shuffle toggle — accent when on, faint when off.
class _ShuffleToggle extends StatelessWidget {
  const _ShuffleToggle();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, bool>(
      selector: (_, ps) => ps.isShuffleEnabled,
      builder: (context, shuffle, _) => IconButton(
        icon: const Icon(Icons.shuffle),
        iconSize: 16,
        color: shuffle ? AppColors.accent : AppColors.faint,
        hoverColor: AppColors.surface2,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        tooltip: shuffle ? 'Shuffle: ON' : 'Shuffle: OFF',
        onPressed: context.read<AudioPlayerService>().toggleShuffle,
      ),
    );
  }
}

/// Repeat toggle — cycles off → all → one, accent whenever it isn't off.
class _RepeatToggle extends StatelessWidget {
  const _RepeatToggle();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, RepeatMode>(
      selector: (_, ps) => ps.repeatMode,
      builder: (context, repeat, _) => IconButton(
        icon: Icon(repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat),
        iconSize: 16,
        color: repeat == RepeatMode.off ? AppColors.faint : AppColors.accent,
        hoverColor: AppColors.surface2,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        tooltip: switch (repeat) {
          RepeatMode.off => 'Repeat: OFF',
          RepeatMode.all => 'Repeat: ALL',
          RepeatMode.one => 'Repeat: ONE',
        },
        onPressed: context.read<AudioPlayerService>().toggleRepeatMode,
      ),
    );
  }
}
