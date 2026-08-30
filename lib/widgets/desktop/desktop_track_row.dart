import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../theme/app_colors.dart';
import '../add_to_playlist.dart';
import '../cover_art.dart';
import 'desktop_primitives.dart';
import '../favourite_button.dart';

/// One track row in a desktop list.
///
/// Selects on `currentTrack?.id` (not the whole player) so a row doesn't
/// rebuild on every position tick — same reason [TrackTile] does, which this
/// is the desktop counterpart to. The phone keeps [TrackTile]; the two
/// layouts diverge too far (numbered column, serif title, inline playing
/// glyph) to be worth one widget full of form-factor branches.
class DesktopTrackRow extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  /// 1-based number shown in the left column. Null hides the column.
  final int? number;

  const DesktopTrackRow({
    super.key,
    required this.track,
    required this.onTap,
    this.number,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, String?>(
      selector: (_, ps) => ps.currentTrack?.id,
      builder: (context, currentId, _) {
        final isCurrent = currentId == track.id;

        return _QueueContextMenu(
          track: track,
          child: HoverRow(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            background: isCurrent ? AppColors.accentSoft : null,
            builder: (hovered) => Row(
              children: [
                if (number case final n?) ...[
                  SizedBox(
                    width: 22,
                    child: Text(
                      '$n',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: isCurrent
                            ? AppColors.accentText
                            : AppColors.faint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                CoverArt(track, size: 40, radius: 6, showPlaceholder: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: serifStyle(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w600 : null,
                      color: isCurrent ? AppColors.accentText : AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (isCurrent) ...[
                  const PlayingBars(),
                  const SizedBox(width: 12),
                ],
                // Hidden (but still occupying its width) until the row is
                // hovered, unless it's already a favourite — see
                // FavouriteButton.
                FavouriteButton(track: track, visible: hovered),
                const SizedBox(width: 8),
                Text(
                  track.formattedDuration,
                  style: TextStyle(
                    fontSize: 12,
                    color: isCurrent ? AppColors.accentText : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Right-click to queue a track.
///
/// The phone list queues by swiping right, a gesture desktop has no
/// equivalent for, and the mock shows no visible affordance for it. A context
/// menu keeps the capability without adding anything to the resting design.
class _QueueContextMenu extends StatelessWidget {
  final Track track;
  final Widget child;

  const _QueueContextMenu({required this.track, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) => _show(context, details.globalPosition),
      child: child,
    );
  }

  Future<void> _show(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final playerService = context.read<AudioPlayerService>();
    final messenger = ScaffoldMessenger.of(context);
    final hadTrack = playerService.currentTrack != null;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'queue',
          child: Row(
            children: [
              Icon(Icons.queue_music, size: 18),
              SizedBox(width: 10),
              Text('Add to queue'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add, size: 18),
              SizedBox(width: 10),
              Text('Add to playlist…'),
            ],
          ),
        ),
      ],
    );

    if (selected == 'playlist') {
      if (context.mounted) await AddToPlaylist.show(context, [track]);
      return;
    }
    if (selected != 'queue') return;
    await playerService.addToQueue(track);
    // With nothing playing, addToQueue starts the track instead of queueing
    // it — announcing "added to queue" then would be a lie.
    if (!hadTrack) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Added to queue: ${track.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}
