import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../services/favourites_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/desktop/desktop_primitives.dart';
import '../../widgets/desktop/desktop_track_row.dart';
import 'desktop_shell.dart';

/// The starred songs, newest first.
///
/// Deliberately has no search field: the point of this list is that it is
/// already the short one. It also doesn't scan — [FavouritesService] holds the
/// whole list in memory, so this just renders it.
class DesktopFavouritesScreen extends StatelessWidget {
  const DesktopFavouritesScreen({super.key});

  void _playTrack(BuildContext context, Track track, List<Track> playlist) {
    final player = context.read<AudioPlayerService>();
    // Already the current track — don't restart it, just show it. Same rule
    // the other desktop lists follow.
    if (player.currentTrack?.id != track.id) {
      player.play(playlist, from: playlist.indexOf(track));
    }
    DesktopPlayerLauncher.openPlayer(context);
  }

  void _playAll(
    BuildContext context,
    List<Track> tracks, {
    required bool shuffled,
  }) {
    if (tracks.isEmpty) return;
    final player = context.read<AudioPlayerService>();
    if (shuffled) {
      player.playShuffled(tracks);
    } else {
      player.play(tracks);
    }
    DesktopPlayerLauncher.openPlayer(context);
  }

  @override
  Widget build(BuildContext context) {
    final favourites = context.watch<FavouritesService>();
    final tracks = favourites.starred;

    return ColoredBox(
      color: AppColors.win,
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Favourites',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(favourites),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => _playAll(context, tracks, shuffled: false),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Play All'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => _playAll(context, tracks, shuffled: true),
                  icon: const Icon(Icons.shuffle, size: 16),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Tracks'),
            const SizedBox(height: 6),
            Expanded(child: _buildBody(context, favourites, tracks)),
          ],
        ),
      ),
    );
  }

  String _subtitle(FavouritesService favourites) {
    if (favourites.isLoading && !favourites.isLoaded) return 'Loading…';
    final count = favourites.starred.length;
    return count == 1 ? '1 track' : '$count tracks';
  }

  Widget _buildBody(
    BuildContext context,
    FavouritesService favourites,
    List<Track> tracks,
  ) {
    if (favourites.isLoading && !favourites.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    // An error with nothing loaded is a dead end and needs the retry; an error
    // *after* a successful load (a rejected star) is surfaced by the toggle
    // site instead, and must not replace a list that is still good.
    if (!favourites.isLoaded && favourites.error != null) {
      return DesktopErrorState(
        message: favourites.error!,
        onRetry: () => context.read<FavouritesService>().load(),
      );
    }

    if (tracks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_border, size: 40, color: AppColors.faint),
              SizedBox(height: 12),
              Text(
                'No favourites yet',
                style: TextStyle(fontSize: 15, color: AppColors.muted),
              ),
              SizedBox(height: 6),
              Text(
                'Tap the heart on any track to keep it here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.faint),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return DesktopTrackRow(
          track: track,
          number: index + 1,
          onTap: () => _playTrack(context, track, tracks),
        );
      },
    );
  }
}
