import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
                color: Colors.grey[400],
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
                  final queue = ps.queue;
                  if (queue.isEmpty) {
                    return const Center(child: Text('Queue is empty'));
                  }
                  return ReorderableListView.builder(
                    scrollController: scrollController,
                    itemCount: queue.length,
                    onReorder: (oldIdx, newIdx) {
                      if (newIdx > oldIdx) newIdx--;
                      ps.moveInQueue(oldIdx, newIdx);
                    },
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      return Dismissible(
                        key: ValueKey('queue-${track.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red.shade600,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => ps.removeFromQueue(index),
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
                          ),
                          subtitle: Text(track.formattedDuration),
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child:
                                  Icon(Icons.drag_handle, color: Colors.grey),
                            ),
                          ),
                        ),
                      );
                    },
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
