import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../services/auth_service.dart';
import '../../services/library_scanner.dart';
import '../../services/playlists_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/add_to_playlist.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/desktop/desktop_primitives.dart';
import '../../widgets/desktop/desktop_track_row.dart';
import 'desktop_all_tracks_screen.dart';
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
    Navigator.of(context).push(DesktopPlaylistScreen.route(playlist.id));
  }

  void _openAllTracks() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'All Tracks'),
        builder: (_) => const DesktopAllTracksScreen(),
      ),
    );
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
                  onPressed: () => createPlaylistWithPrompt(context),
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
      return _ErrorState(
        message: service.error!,
        onRetry: () => context.read<PlaylistsService>().load(),
      );
    }
    if (service.playlists.isEmpty) {
      // All Tracks still shows — the list is never truly empty.
      return ListView(
        children: [
          _buildBuiltIns(),
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Column(
              children: [
                Text(
                  'No playlists yet',
                  style: TextStyle(fontSize: 15, color: AppColors.muted),
                ),
                SizedBox(height: 6),
                Text(
                  'Create one above, or right-click a track to add it to one.',
                  style: TextStyle(fontSize: 13, color: AppColors.faint),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      // One extra leading row for All Tracks, plus the divider under it.
      itemCount: service.playlists.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _buildBuiltIns();
        final playlist = service.playlists[i - 1];
        return _PlaylistRow(
          playlist: playlist,
          editable: playlist.isEditableBy(username),
          onTap: () => _open(playlist),
        );
      },
    );
  }

  /// The library's own collections, above the user's playlists.
  ///
  /// All Tracks is a *view of the library*, not a playlist: it can't be
  /// renamed, deleted or added to, and it never appears in the add-to-playlist
  /// picker. The divider is what makes that distinction visible rather than
  /// something the user has to discover by right-clicking.
  Widget _buildBuiltIns() {
    final count = context.watch<LibraryScanner>().allTracks.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BuiltInRow(
          icon: Icons.library_music_outlined,
          name: 'All Tracks',
          summary: count == 0
              ? 'Everything in your library'
              : '${_thousands(count)} tracks',
          onTap: _openAllTracks,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ],
    );
  }

  static String _thousands(int n) {
    final digits = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// A library collection in the playlists list — same shape as a playlist row,
/// deliberately, but with no overflow menu because there is nothing to rename
/// or delete.
class _BuiltInRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String summary;
  final VoidCallback onTap;

  const _BuiltInRow({
    required this.icon,
    required this.name,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 20, color: AppColors.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: serifStyle(fontSize: 14, color: AppColors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One playlist in the list: cover, name, summary, and an overflow menu for
/// rename/delete (only where the user actually owns it).
class _PlaylistRow extends StatelessWidget {
  final Playlist playlist;
  final bool editable;
  final VoidCallback onTap;

  const _PlaylistRow({
    required this.playlist,
    required this.editable,
    required this.onTap,
  });

  Future<void> _rename(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      // The dialog owns its controller — see PlaylistNameDialog for why.
      builder: (_) => PlaylistNameDialog(
        initialName: playlist.name,
        title: 'Rename playlist',
        actionLabel: 'Rename',
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    await context.read<PlaylistsService>().rename(playlist.id, name);
  }

  Future<void> _delete(BuildContext context) async {
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
    if (confirmed != true || !context.mounted) return;
    await context.read<PlaylistsService>().delete(playlist.id);
  }

  @override
  Widget build(BuildContext context) {
    return HoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          CoverArt(playlist, size: 40, radius: 6, showPlaceholder: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: serifStyle(fontSize: 14, color: AppColors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  editable
                      ? playlist.summary
                      : '${playlist.summary} · read-only',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (editable)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(
                Icons.more_horiz,
                size: 18,
                color: AppColors.faint,
              ),
              onSelected: (value) =>
                  value == 'rename' ? _rename(context) : _delete(context),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename…')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
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
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Tracks'),
            const SizedBox(height: 6),
            Expanded(child: _buildBody(tracks)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<Track>? tracks) {
    // Null means not fetched yet; empty means a genuinely empty playlist.
    if (tracks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tracks.isEmpty) {
      return const Center(
        child: Text(
          'This playlist is empty.',
          style: TextStyle(color: AppColors.muted),
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 36, color: AppColors.faint),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
