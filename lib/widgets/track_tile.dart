import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import 'cover_art.dart';

/// One track row, used by the home, all-tracks and folder screens. Was three
/// near-identical private tiles that had already drifted — the home screen
/// silently lost swipe-to-queue when the other two gained it. See
/// docs/reviews/2026-08-22-architecture-review.html Candidate 04.
///
/// Selects on `currentTrack?.id` (not the whole player) so this doesn't
/// rebuild on every position update.
class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  /// All-tracks and folder screens number their rows; home doesn't.
  final int? leadingIndex;

  /// Swipe-right to add to the queue. Defaults on — the one behavioral
  /// change from unifying the three tiles: home gains the gesture the other
  /// two already had, closing the drift rather than parameterizing around it.
  final bool swipeToQueue;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.leadingIndex,
    this.swipeToQueue = true,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, String?>(
      selector: (_, ps) => ps.currentTrack?.id,
      builder: (context, currentTrackId, _) {
        final scheme = Theme.of(context).colorScheme;
        final isCurrentTrack = currentTrackId == track.id;
        final index = leadingIndex;

        final tile = ListTile(
          leading: index == null
              ? CoverArt(track, size: 48, showPlaceholder: false)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isCurrentTrack ? scheme.primary : scheme.onSurfaceVariant,
                          fontWeight: isCurrentTrack ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                    CoverArt(track, size: 48, showPlaceholder: false),
                  ],
                ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isCurrentTrack ? FontWeight.bold : null,
              color: isCurrentTrack ? scheme.primary : null,
            ),
          ),
          subtitle: Text(
            track.formattedDuration,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isCurrentTrack
              ? Icon(Icons.equalizer, color: scheme.primary)
              : null,
          onTap: onTap,
        );

        if (!swipeToQueue) return tile;

        return Dismissible(
          key: ValueKey('track-tile-${track.id}'),
          direction: DismissDirection.startToEnd,
          background: Container(
            color: Colors.green.shade600,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.queue_music, color: Colors.white),
                SizedBox(width: 8),
                Text('Add to queue',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            final ps = context.read<AudioPlayerService>();
            final messenger = ScaffoldMessenger.of(context);
            final willQueue = ps.currentTrack != null;
            await ps.addToQueue(track);
            if (willQueue) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('Added to queue: ${track.title}'),
                  duration: const Duration(seconds: 2),
                ));
            }
            return false;
          },
          child: tile,
        );
      },
    );
  }
}
