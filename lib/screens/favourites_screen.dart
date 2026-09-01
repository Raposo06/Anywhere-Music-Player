import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/favourites_service.dart';
import '../utils/responsive.dart';
import '../widgets/centred_message.dart';
import '../widgets/play_actions.dart';
import '../widgets/track_tile.dart';

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
              onPressed: () => playAll(context, tracks),
            ),
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: 'Shuffle',
              onPressed: () => playAll(context, tracks, shuffled: true),
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
      return CentredMessage(
        icon: Icons.error_outline,
        title: favourites.error!,
        action: FilledButton(
          onPressed: () => context.read<FavouritesService>().load(),
          child: const Text('Retry'),
        ),
      );
    }

    if (tracks.isEmpty) {
      return const CentredMessage(
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
          onTap: () => playFromList(context, track, tracks),
        );
      },
    );
  }
}

