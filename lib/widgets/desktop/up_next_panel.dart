import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../theme/app_colors.dart';
import '../cover_art.dart';
import 'desktop_primitives.dart';

/// The 300px queue panel pinned to the right of Now Playing.
///
/// Desktop has the width to keep the queue permanently visible, so it
/// replaces the modal [QueueSheet] here rather than sitting behind a button.
/// The sheet is still what phone uses.
///
/// Two lists feed it and they stay separate, because the service indexes them
/// separately: manually queued tracks ([AudioPlayerService.queue], jumped to
/// by `jumpToQueued`) come first, then whatever the browsing context plays
/// next ([AudioPlayerService.upcomingFromContext], `jumpToUpcoming`).
class UpNextPanel extends StatelessWidget {
  const UpNextPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppMetrics.upNextWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.all(20),
      child: Consumer<AudioPlayerService>(
        builder: (context, ps, _) {
          final current = ps.currentTrack;
          final queued = ps.queue;
          final upcoming = ps.upcomingFromContext;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Up Next'),
              const SizedBox(height: 14),
              if (current != null) ...[
                _QueueRow(track: current, playing: true),
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: queued.isEmpty && upcoming.isEmpty
                    ? const Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'Nothing queued',
                          style: TextStyle(fontSize: 12.5, color: AppColors.faint),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final (index, track) in queued.indexed)
                            _QueueRow(
                              track: track,
                              onTap: () => ps.jumpToQueued(index),
                            ),
                          for (final (index, track) in upcoming.indexed)
                            _QueueRow(
                              track: track,
                              onTap: () => ps.jumpToUpcoming(index),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One row: 36px art, title, and either the duration or — for the playing
/// row — the animated bars glyph.
class _QueueRow extends StatelessWidget {
  final Track track;
  final bool playing;
  final VoidCallback? onTap;

  const _QueueRow({required this.track, this.playing = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: HoverRow(
        onTap: onTap,
        padding: const EdgeInsets.all(6),
        background: playing ? AppColors.accentSoft : null,
        child: Row(
          children: [
            CoverArt(track, size: 36, radius: 6, showPlaceholder: false),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: playing ? FontWeight.w600 : FontWeight.w400,
                  color: playing ? AppColors.accentText : AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (playing)
              const PlayingBars(size: 13)
            else
              Text(
                track.formattedDuration,
                style: const TextStyle(fontSize: 11, color: AppColors.faint),
              ),
          ],
        ),
      ),
    );
  }
}
