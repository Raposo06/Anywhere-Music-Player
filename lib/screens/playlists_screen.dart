import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/auth_service.dart';
import '../services/library_scanner.dart';
import '../services/playlists_service.dart';
import '../utils/responsive.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/cover_art.dart';
import '../widgets/track_tile.dart';
import 'all_tracks_screen.dart';
import 'player_screen.dart';

/// The phone's playlists list. Counterpart to `DesktopPlaylistsScreen`;
/// the two share [PlaylistsService] and differ only in chrome.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlaylistsService>().load();
    });
  }

  void _open(Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistScreen(playlistId: playlist.id),
      ),
    );
  }

  void _openAllTracks() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AllTracksScreen()));
  }

  /// The library's own collection, above the user's playlists.
  ///
  /// All Tracks is a *view of the library*, not a playlist: nothing to rename
  /// or delete, and it never appears in the add-to-playlist picker. The
  /// divider is what makes that visible.
  Widget _buildBuiltIns(BuildContext context) {
    final count = context.watch<LibraryScanner>().allTracks.length;
    return Column(
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.library_music)),
          title: const Text('All Tracks'),
          subtitle: Text(
            count == 0 ? 'Everything in your library' : '$count tracks',
          ),
          onTap: _openAllTracks,
        ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _confirmDelete(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${playlist.name}"?'),
        content: const Text(
          'This removes the playlist from the server. The songs themselves '
          'are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<PlaylistsService>().delete(playlist.id);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PlaylistsService>();
    final username = context.read<AuthService>().currentUser?.username;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New playlist',
            onPressed: () => createPlaylistWithPrompt(context),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.getContentMaxWidth(context) ?? double.infinity,
          ),
          child: RefreshIndicator(
            onRefresh: () => context.read<PlaylistsService>().load(),
            child: _buildBody(service, username),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(PlaylistsService service, String? username) {
    if (service.isLoading && !service.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!service.isLoaded && service.error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: service.error!,
        action: FilledButton(
          onPressed: () => context.read<PlaylistsService>().load(),
          child: const Text('Retry'),
        ),
      );
    }
    if (service.playlists.isEmpty) {
      // All Tracks still shows — the list is never truly empty.
      return ListView(
        children: [
          _buildBuiltIns(context),
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Text(
              'No playlists yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      // One extra leading row for All Tracks.
      itemCount: service.playlists.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _buildBuiltIns(context);
        final playlist = service.playlists[i - 1];
        final editable = playlist.isEditableBy(username);
        return ListTile(
          leading: CoverArt(playlist, size: 48, showPlaceholder: false),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            editable ? playlist.summary : '${playlist.summary} · read-only',
          ),
          trailing: editable
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(playlist),
                )
              : null,
          onTap: () => _open(playlist),
        );
      },
    );
  }
}

/// One playlist's tracks, on the phone.
class PlaylistScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PlaylistsService>().loadTracks(widget.playlistId);
      }
    });
  }

  void _playTrack(Track track, List<Track> tracks) {
    final player = context.read<AudioPlayerService>();
    if (player.currentTrack?.id != track.id) {
      player.play(tracks, from: tracks.indexOf(track));
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  void _playAll(List<Track> tracks, {required bool shuffled}) {
    if (tracks.isEmpty) return;
    final player = context.read<AudioPlayerService>();
    if (shuffled) {
      player.playShuffled(tracks);
    } else {
      player.play(tracks);
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  /// Whether this playlist accepts edits — see [Playlist.isEditableBy].
  bool get _editable {
    final playlist = context.read<PlaylistsService>().byId(widget.playlistId);
    final username = context.read<AuthService>().currentUser?.username;
    return playlist?.isEditableBy(username) ?? false;
  }

  Future<void> _remove(Track track, int index) async {
    await context.read<PlaylistsService>().removeTrack(
      widget.playlistId,
      index,
      trackId: track.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PlaylistsService>();
    final playlist = service.byId(widget.playlistId);
    final tracks = service.tracksOf(widget.playlistId);
    final hasTracks = tracks != null && tracks.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? 'Playlist'),
        actions: [
          if (hasTracks) ...[
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Play all',
              onPressed: () => _playAll(tracks, shuffled: false),
            ),
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: 'Shuffle',
              onPressed: () => _playAll(tracks, shuffled: true),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<PlaylistsService>().loadTracks(
          widget.playlistId,
          force: true,
        ),
        child: _buildBody(tracks),
      ),
    );
  }

  Widget _buildBody(List<Track>? tracks) {
    // Null means not fetched yet; empty means a genuinely empty playlist.
    if (tracks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tracks.isEmpty) {
      return const _Message(
        icon: Icons.queue_music,
        title: 'This playlist is empty',
        subtitle: 'Long-press a track anywhere to add it here.',
      );
    }
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, i) => TrackTile(
        track: tracks[i],
        leadingIndex: i,
        onRemoveFromPlaylist: _editable ? () => _remove(tracks[i], i) : null,
        onTap: () => _playTrack(tracks[i], tracks),
      ),
    );
  }
}

/// Empty and error states, kept scrollable so pull-to-refresh still works
/// when there are no rows.
class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _Message({
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
