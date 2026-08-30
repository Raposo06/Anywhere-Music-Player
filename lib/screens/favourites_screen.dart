import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/favourites_service.dart';
import '../utils/responsive.dart';
import '../widgets/track_tile.dart';
import 'player_screen.dart';

/// The phone's starred songs, newest first.
///
/// Counterpart to `DesktopFavouritesScreen`; the two share
/// [FavouritesService] and diverge only in chrome, the same way the rest of
/// the phone and desktop layouts do (see docs/decisions.md).
///
/// Pull to refresh — the list can go stale if you starred something from
/// another client, and the phone has no "click the active tab" gesture to
/// re-sync with the way the desktop sidebar does.
class FavouritesScreen extends StatelessWidget {
  const FavouritesScreen({super.key});

  void _playTrack(BuildContext context, Track track, List<Track> playlist) {
    final playerService = context.read<AudioPlayerService>();
    // Already the current track — don't restart it, just open the player.
    // Same rule the other phone lists follow.
    if (playerService.currentTrack?.id != track.id) {
      playerService.play(playlist, from: playlist.indexOf(track));
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  void _playAll(
    BuildContext context,
    List<Track> tracks, {
    required bool shuffled,
  }) {
    if (tracks.isEmpty) return;
    final playerService = context.read<AudioPlayerService>();
    if (shuffled) {
      playerService.playShuffled(tracks);
    } else {
      playerService.play(tracks);
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final favourites = context.watch<FavouritesService>();
    final tracks = favourites.starred;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourites'),
        actions: [
          if (tracks.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Play all',
              onPressed: () => _playAll(context, tracks, shuffled: false),
            ),
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: 'Shuffle',
              onPressed: () => _playAll(context, tracks, shuffled: true),
            ),
          ],
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.getContentMaxWidth(context) ?? double.infinity,
          ),
          child: RefreshIndicator(
            onRefresh: () => context.read<FavouritesService>().load(),
            child: _buildBody(context, favourites, tracks),
          ),
        ),
      ),
    );
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
    // *after* a successful load (a rejected star) is surfaced as a SnackBar
    // instead, and must not replace a list that is still good.
    if (!favourites.isLoaded && favourites.error != null) {
      return _CentredMessage(
        icon: Icons.error_outline,
        title: favourites.error!,
        action: FilledButton(
          onPressed: () => context.read<FavouritesService>().load(),
          child: const Text('Retry'),
        ),
      );
    }

    if (tracks.isEmpty) {
      return const _CentredMessage(
        icon: Icons.favorite_border,
        title: 'No favourites yet',
        subtitle: 'Tap the heart on any track to keep it here.',
      );
    }

    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return TrackTile(
          track: track,
          leadingIndex: index,
          onTap: () => _playTrack(context, track, tracks),
        );
      },
    );
  }
}

/// Empty and error states, both of which must stay scrollable so
/// [RefreshIndicator] can still be pulled when the list has no rows.
class _CentredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _CentredMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 48, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  if (subtitle case final subtitle?) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                  if (action case final action?) ...[
                    const SizedBox(height: 20),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
