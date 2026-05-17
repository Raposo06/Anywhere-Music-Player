import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';

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
      initialChildSize: 0.75,
      minChildSize: 0.4,
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
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Queue',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
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
                  final playlist = ps.playlist;
                  final currentIndex = ps.currentIndex;

                  if (playlist.isEmpty) {
                    return const Center(child: Text('Queue is empty'));
                  }

                  final upcoming = <_QueueEntry>[];
                  for (int i = 0; i < playlist.length; i++) {
                    if (i == currentIndex) continue;
                    if (i < currentIndex) continue;
                    upcoming.add(_QueueEntry(track: playlist[i], playlistIndex: i));
                  }

                  final currentTrack =
                      currentIndex >= 0 && currentIndex < playlist.length
                          ? playlist[currentIndex]
                          : null;

                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      if (currentTrack != null) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Now Playing',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _QueueTile(
                            track: currentTrack,
                            isCurrent: true,
                          ),
                        ),
                      ],
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            upcoming.isEmpty ? 'No upcoming tracks' : 'Up Next',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ),
                      ),
                      if (upcoming.isNotEmpty)
                        SliverReorderableList(
                          itemCount: upcoming.length,
                          onReorder: (oldIdx, newIdx) {
                            final from = upcoming[oldIdx].playlistIndex;
                            int to;
                            if (newIdx >= upcoming.length) {
                              to = upcoming.last.playlistIndex;
                            } else if (newIdx > oldIdx) {
                              to = upcoming[newIdx - 1].playlistIndex;
                            } else {
                              to = upcoming[newIdx].playlistIndex;
                            }
                            ps.moveInQueue(from, to);
                          },
                          itemBuilder: (context, index) {
                            final entry = upcoming[index];
                            return _DismissibleQueueTile(
                              key: ValueKey('queue-${entry.playlistIndex}-${entry.track.id}'),
                              entry: entry,
                              index: index,
                              onRemove: () =>
                                  ps.removeFromQueue(entry.playlistIndex),
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
}

class _QueueEntry {
  final Track track;
  final int playlistIndex;
  _QueueEntry({required this.track, required this.playlistIndex});
}

class _DismissibleQueueTile extends StatelessWidget {
  final _QueueEntry entry;
  final int index;
  final VoidCallback onRemove;

  const _DismissibleQueueTile({
    super.key,
    required this.entry,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss-${entry.playlistIndex}-${entry.track.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade600,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: _QueueTile(
        track: entry.track,
        isCurrent: false,
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.drag_handle, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final Widget? trailing;

  const _QueueTile({
    required this.track,
    required this.isCurrent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isCurrent ? Colors.blue.withValues(alpha: 0.08) : null,
      child: ListTile(
        leading: track.coverArtUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: track.coverArtUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.music_note, size: 48),
                ),
              )
            : const Icon(Icons.music_note, size: 48),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.bold : null,
            color: isCurrent ? Colors.blue : null,
          ),
        ),
        subtitle: Text(
          track.formattedDuration,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isCurrent
            ? const Icon(Icons.equalizer, color: Colors.blue)
            : trailing,
      ),
    );
  }
}
