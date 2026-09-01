import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/auth_service.dart';
import '../services/playlists_service.dart';
import '../utils/responsive.dart';
import '../widgets/add_songs_to_playlist.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/centred_message.dart';
import '../widgets/cover_art.dart';
import '../widgets/play_actions.dart';
import '../widgets/track_tile.dart';

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

  /// Create, then open it — a new playlist is empty, and the only useful next
  /// step is putting songs in it.
  Future<void> _createAndOpen() async {
    final created = await createPlaylistWithPrompt(context);
    if (created == null || !mounted) return;
    _open(created);
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
            onPressed: _createAndOpen,
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
      return CentredMessage(
        icon: Icons.error_outline,
        title: service.error!,
        action: FilledButton(
          onPressed: () => context.read<PlaylistsService>().load(),
          child: const Text('Retry'),
        ),
      );
    }
    if (service.playlists.isEmpty) {
      return const CentredMessage(
        icon: Icons.queue_music,
        title: 'No playlists yet',
        subtitle: 'Create one with +, or long-press a track to add it to one.',
      );
    }

    return ListView.builder(
      itemCount: service.playlists.length,
      itemBuilder: (context, i) {
        final playlist = service.playlists[i];
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

  Future<void> _addSongs(Playlist playlist) =>
      AddSongsToPlaylist.show(context, playlist);

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
              onPressed: () => playAll(context, tracks),
            ),
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: 'Shuffle',
              onPressed: () => playAll(context, tracks, shuffled: true),
            ),
          ],
          if (playlist != null && _editable)
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Add songs',
              onPressed: () => _addSongs(playlist),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<PlaylistsService>().loadTracks(
          widget.playlistId,
          force: true,
        ),
        child: _buildBody(playlist, tracks),
      ),
    );
  }

  Widget _buildBody(Playlist? playlist, List<Track>? tracks) {
    // Null means not fetched yet; empty means a genuinely empty playlist.
    if (tracks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tracks.isEmpty) {
      return CentredMessage(
        icon: Icons.queue_music,
        title: 'This playlist is empty',
        subtitle: playlist != null && _editable
            ? null
            : 'Long-press a track anywhere to add it here.',
        action: playlist != null && _editable
            ? FilledButton.icon(
                onPressed: () => _addSongs(playlist),
                icon: const Icon(Icons.search),
                label: const Text('Add songs'),
              )
            : null,
      );
    }
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, i) => TrackTile(
        track: tracks[i],
        leadingIndex: i,
        onRemoveFromPlaylist: _editable ? () => _remove(tracks[i], i) : null,
        onTap: () => playFromList(context, tracks[i], tracks),
      ),
    );
  }
}

