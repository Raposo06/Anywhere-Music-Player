import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../screens/player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, Track?>(
      selector: (_, ps) => ps.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return _MiniPlayerContent(track: track);
      },
    );
  }
}

class _MiniPlayerContent extends StatelessWidget {
  final Track track;

  const _MiniPlayerContent({required this.track});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlayerScreen()),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withAlpha(50),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar at the top of the mini player
            _MiniProgressBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Album art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: track.coverArtUrl != null
                          ? CachedNetworkImage(
                              imageUrl: track.coverArtUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.music_note, size: 24),
                              ),
                            )
                          : Container(
                              color: Colors.grey[800],
                              child: const Icon(Icons.music_note, size: 24),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title and artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Playback controls
                  _MiniControls(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
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
          minHeight: 2,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

class _MiniControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final playerService = context.read<AudioPlayerService>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 28,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => playerService.playPrevious(),
        ),
        StreamBuilder<bool>(
          stream: playerService.playingStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return IconButton(
              icon: Icon(
                isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
              ),
              iconSize: 36,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => playerService.togglePlayPause(),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 28,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => playerService.playNext(),
        ),
      ],
    );
  }
}
