import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import 'cover_art.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const QueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('Queue', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Consumer<AudioPlayerService>(
                builder: (context, ps, _) {
                  final current = ps.currentTrack;
                  final manual = ps.queue;
                  final upcoming = ps.upcomingFromContext;

                  if (current == null && manual.isEmpty && upcoming.isEmpty) {
                    return const Center(child: Text('Queue is empty'));
                  }

                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      // Now Playing
                      if (current != null) ...[
                        _label(context, 'Now Playing'),
                        SliverToBoxAdapter(
                          child: _TrackRow(
                            track: current,
                            highlight: true,
                          ),
                        ),
                      ],

                      // Next in Queue (manual adds)
                      if (manual.isNotEmpty) _label(context, 'Next in Queue'),
                      SliverReorderableList(
                        itemCount: manual.length,
                        onReorderItem: (oldIdx, newIdx) {
                          ps.moveInQueue(oldIdx, newIdx);
                        },
                        itemBuilder: (context, index) {
                          final track = manual[index];
                          return _TrackRow(
                            key: ValueKey('mq-${track.id}-$index'),
                            track: track,
                            reorderIndex: index,
                            onTap: () => ps.jumpToQueued(index),
                            onDismissed: () => ps.removeFromQueue(index),
                          );
                        },
                      ),

                      // Next from the browsing context (auto playlist/shuffle)
                      if (upcoming.isNotEmpty)
                        _label(context, 'Next from playlist'),
                      SliverReorderableList(
                        itemCount: upcoming.length,
                        onReorderItem: (oldIdx, newIdx) {
                          ps.reorderUpcoming(oldIdx, newIdx);
                        },
                        itemBuilder: (context, index) {
                          final track = upcoming[index];
                          return _TrackRow(
                            key: ValueKey('auto-${track.id}-$index'),
                            track: track,
                            reorderIndex: index,
                            onTap: () => ps.jumpToUpcoming(index),
                          );
                        },
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _label(BuildContext context, String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// A single row in the queue sheet. Optionally draggable (when [reorderIndex]
/// is provided) and dismissible (when [onDismissed] is provided).
class _TrackRow extends StatelessWidget {
  final Track track;
  final bool highlight;
  final int? reorderIndex;
  final VoidCallback? onTap;
  final VoidCallback? onDismissed;

  const _TrackRow({
    super.key,
    required this.track,
    this.highlight = false,
    this.reorderIndex,
    this.onTap,
    this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = ListTile(
      leading: CoverArt(track, size: 48, showPlaceholder: false),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: highlight
            ? TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)
            : null,
      ),
      subtitle: Text(track.formattedDuration),
      trailing: highlight
          ? Icon(Icons.equalizer, color: scheme.primary)
          : (reorderIndex != null
              ? ReorderableDragStartListener(
                  index: reorderIndex!,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.drag_handle,
                        color: scheme.onSurfaceVariant),
                  ),
                )
              : null),
      onTap: onTap,
    );

    // The reorder drag proxy lifts this row out of the tree, so it needs its
    // own Material ancestor or ListTile throws "No Material widget found".
    final content = onDismissed == null
        ? tile
        : Dismissible(
            key: ValueKey('dismiss-${track.id}-$reorderIndex'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red.shade600,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) => onDismissed!(),
            child: tile,
          );

    return Material(type: MaterialType.transparency, child: content);
  }
}
