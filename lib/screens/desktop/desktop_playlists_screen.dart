import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../services/auth_service.dart';
import '../../services/playlists_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/add_songs_to_playlist.dart';
import '../../widgets/add_to_playlist.dart';
import '../../widgets/desktop/desktop_primitives.dart';
import '../../widgets/desktop/desktop_track_row.dart';
import 'desktop_shell.dart';

/// The playlists list — the root of the Playlists destination's navigator.
///
/// Drill-down works like the library's: this pushes [DesktopPlaylistScreen]
/// onto the same nested navigator, so the shell's back handling (Alt + ← and
/// Escape) unwinds it for free.
class DesktopPlaylistsScreen extends StatefulWidget {
  const DesktopPlaylistsScreen({super.key});

  @override
  State<DesktopPlaylistsScreen> createState() => _DesktopPlaylistsScreenState();
}

class _DesktopPlaylistsScreenState extends State<DesktopPlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlaylistsService>().load();
    });
  }

  void _open(Playlist playlist) {
    Navigator.of(
      context,
    ).push(DesktopPlaylistScreen.route(playlist.id, name: playlist.name));
  }

  /// Create, then open it — a new playlist is empty, and the only useful next
  /// step is putting songs in it.
  Future<void> _createAndOpen() async {
    final created = await createPlaylistWithPrompt(context);
    if (created == null || !mounted) return;
    _open(created);
  }

  /// Play a playlist without opening it.
  ///
  /// Its tracks are fetched on demand — the list view only knows counts — so
  /// this loads first and then plays, mirroring what the folder cards do with
  /// their own play button.
  Future<void> _playPlaylist(Playlist playlist) async {
    final service = context.read<PlaylistsService>();
    await service.loadTracks(playlist.id);
    final tracks = service.tracksOf(playlist.id);
    if (tracks == null || tracks.isEmpty || !mounted) return;
    context.read<AudioPlayerService>().play(tracks);
    if (mounted) DesktopPlayerLauncher.openPlayer(context);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PlaylistsService>();
    final username = context.read<AuthService>().currentUser?.username;

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
                        'Playlists',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(service),
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
                  onPressed: _createAndOpen,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New playlist'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildBody(service, username)),
          ],
        ),
      ),
    );
  }

  String _subtitle(PlaylistsService service) {
    if (service.isLoading && !service.isLoaded) return 'Loading…';
    final n = service.playlists.length;
    return n == 1 ? '1 playlist' : '$n playlists';
  }

  Widget _buildBody(PlaylistsService service, String? username) {
    if (service.isLoading && !service.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!service.isLoaded && service.error != null) {
      return DesktopErrorState(
        message: service.error!,
        onRetry: () => context.read<PlaylistsService>().load(),
      );
    }

    return ListView(
      children: [
        _grid([
          for (final playlist in service.playlists)
            _PlaylistCard(
              playlist: playlist,
              editable: playlist.isEditableBy(username),
              onOpen: () => _open(playlist),
              onPlay: () => _playPlaylist(playlist),
            ),
        ]),
        if (service.playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text(
              'No playlists yet — create one above, or right-click a track '
              'to add it to one.',
              style: TextStyle(fontSize: 13, color: AppColors.faint),
            ),
          ),
      ],
    );
  }

  /// The same grid geometry the library's folder cards use, so the two screens
  /// line up column-for-column at any window width.
  Widget _grid(List<Widget> children) {
    return GridView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 0.86,
      ),
      children: children,
    );
  }
}

/// A playlist as a [HoverCoverCard], matching the library's folder cards —
/// plus an overflow menu for rename/delete where the playlist is editable.
///
/// Navidrome generates a mosaic cover for a playlist, so most have real art;
/// the fallback is the same queue glyph used elsewhere for playlists.
class _PlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final bool editable;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  const _PlaylistCard({
    required this.playlist,
    required this.editable,
    required this.onOpen,
    required this.onPlay,
  });

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      // The dialog owns its controller — see PlaylistNameDialog for why.
      builder: (_) => PlaylistNameDialog(
        initialName: widget.playlist.name,
        title: 'Rename playlist',
        actionLabel: 'Rename',
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await context.read<PlaylistsService>().rename(widget.playlist.id, name);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${widget.playlist.name}"?'),
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
    await context.read<PlaylistsService>().delete(widget.playlist.id);
  }

  @override
  Widget build(BuildContext context) {
    return HoverCoverCard(
      source: widget.playlist,
      fallbackIcon: Icons.queue_music,
      title: widget.playlist.name,
      subtitle: widget.editable
          ? widget.playlist.summary
          : '${widget.playlist.summary} · read-only',
      playTooltip: 'Play this playlist',
      onOpen: widget.onOpen,
      onPlay: widget.onPlay,
      // Always present rather than hover-gated, like the play button: the
      // design keeps card affordances visible.
      overlay: widget.editable
          ? Positioned(
              right: 4,
              top: 4,
              child: PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: Colors.white,
                ),
                onSelected: (value) =>
                    value == 'rename' ? _rename() : _delete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename…')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            )
          : null,
    );
  }
}

/// One playlist's tracks.
class DesktopPlaylistScreen extends StatefulWidget {
  final String playlistId;

  const DesktopPlaylistScreen({super.key, required this.playlistId});

  /// The route the list pushes. Named so the window chrome can show the
  /// playlist as context — see `_TopRouteObserver` in desktop_shell.dart.
  static Route<void> route(String playlistId, {String? name}) {
    return MaterialPageRoute(
      settings: RouteSettings(name: name),
      builder: (_) => DesktopPlaylistScreen(playlistId: playlistId),
    );
  }

  @override
  State<DesktopPlaylistScreen> createState() => _DesktopPlaylistScreenState();
}

class _DesktopPlaylistScreenState extends State<DesktopPlaylistScreen> {
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
    DesktopPlayerLauncher.openPlayer(context);
  }

  void _playAll(List<Track> tracks, {required bool shuffled}) {
    if (tracks.isEmpty) return;
    final player = context.read<AudioPlayerService>();
    if (shuffled) {
      player.playShuffled(tracks);
    } else {
      player.play(tracks);
    }
    DesktopPlayerLauncher.openPlayer(context);
  }

  /// Whether this playlist accepts edits. Playlists owned by someone else are
  /// visible but not modifiable — see [Playlist.isEditableBy].
  bool get _editable {
    final playlist = context.read<PlaylistsService>().byId(widget.playlistId);
    final username = context.read<AuthService>().currentUser?.username;
    return playlist?.isEditableBy(username) ?? false;
  }

  Future<void> _addSongs(Playlist playlist) =>
      AddSongsToPlaylist.show(context, playlist);

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

    return ColoredBox(
      color: AppColors.win,
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Crumb(onTap: () => Navigator.of(context).maybePop()),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist?.name ?? 'Playlist',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        playlist?.summary ?? '',
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
                  onPressed: (tracks == null || tracks.isEmpty)
                      ? null
                      : () => _playAll(tracks, shuffled: false),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Play All'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (tracks == null || tracks.isEmpty)
                      ? null
                      : () => _playAll(tracks, shuffled: true),
                  icon: const Icon(Icons.shuffle, size: 16),
                  label: const Text('Shuffle'),
                ),
                if (playlist != null && _editable) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _addSongs(playlist),
                    icon: const Icon(Icons.playlist_add, size: 16),
                    label: const Text('Add songs'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Tracks'),
            const SizedBox(height: 6),
            Expanded(child: _buildBody(playlist, tracks)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Playlist? playlist, List<Track>? tracks) {
    // Null means not fetched yet; empty means a genuinely empty playlist.
    if (tracks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This playlist is empty.',
              style: TextStyle(color: AppColors.muted),
            ),
            if (playlist != null && _editable) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _addSongs(playlist),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Add songs'),
              ),
            ],
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, i) => DesktopTrackRow(
        track: tracks[i],
        number: i + 1,
        onTap: () => _playTrack(tracks[i], tracks),
        onRemoveFromPlaylist: _editable ? () => _remove(tracks[i], i) : null,
      ),
    );
  }
}

/// The "‹ Playlists" step back to the list.
class _Crumb extends StatelessWidget {
  final VoidCallback onTap;

  const _Crumb({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left, size: 16, color: AppColors.muted),
              SizedBox(width: 2),
              Text(
                'Playlists',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
