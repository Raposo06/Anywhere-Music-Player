import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../models/folder.dart';
import '../services/library_scanner.dart';
import '../services/audio_player_service.dart';
import '../utils/responsive.dart';
import '../widgets/mini_player.dart';
import 'player_screen.dart';

class FolderDetailScreen extends StatefulWidget {
  final String folderId;
  final String folderName;

  const FolderDetailScreen({
    super.key,
    required this.folderId,
    required this.folderName,
  });

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  List<Track> _tracks = [];
  List<Folder> _subfolders = [];

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  void _loadContents() {
    final scanner = context.read<LibraryScanner>();
    debugPrint('FolderDetail: loading folderId="${widget.folderId}"');
    final contents = scanner.getFolderContents(widget.folderId);
    debugPrint('FolderDetail: got ${contents.folders.length} subfolders, ${contents.tracks.length} tracks');
    for (final f in contents.folders.take(5)) {
      debugPrint('FolderDetail: subfolder path="${f.folderPath}" name="${f.displayName}"');
    }
    setState(() {
      _subfolders = contents.folders;
      _tracks = contents.tracks;
    });
  }

  void _playTrack(Track track) {
    final playerService = context.read<AudioPlayerService>();
    final trackIndex = _tracks.indexOf(track);
    playerService.playPlaylist(_tracks, trackIndex);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _playAll() {
    // Play all tracks recursively (this folder + subfolders)
    final scanner = context.read<LibraryScanner>();
    final allTracks = scanner.getAllTracksInFolder(widget.folderId);
    if (allTracks.isEmpty) return;

    final playerService = context.read<AudioPlayerService>();
    playerService.playPlaylist(allTracks, 0);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _shufflePlay() {
    final scanner = context.read<LibraryScanner>();
    final allTracks = scanner.getAllTracksInFolder(widget.folderId);
    if (allTracks.isEmpty) return;

    final playerService = context.read<AudioPlayerService>();
    // Enable shuffle before starting playlist — playPlaylist will shuffle internally
    if (!playerService.isShuffleEnabled) {
      playerService.toggleShuffle(); // No active playlist, so this just sets the flag
    }
    playerService.playPlaylist(allTracks, 0);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _openSubfolder(Folder folder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(
          folderId: folder.folderPath,
          folderName: folder.displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folderName),
        actions: [
          Selector<AudioPlayerService, bool>(
            selector: (_, ps) => ps.currentTrack != null,
            builder: (context, hasTrack, _) => hasTrack
                ? IconButton(
                    icon: const Icon(Icons.music_note),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PlayerScreen()),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.getContentMaxWidth(context) ?? double.infinity,
          ),
          child: _buildBody(),
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _buildBody() {
    final horizontalPadding = Responsive.getHorizontalPadding(context);

    if (_tracks.isEmpty && _subfolders.isEmpty) {
      return const Center(child: Text('No content found'));
    }

    return Column(
      children: [
        // Header with play buttons
        if (_tracks.isNotEmpty)
          Container(
            padding: EdgeInsets.all(horizontalPadding),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_tracks.length} track(s)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _playAll,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play All'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _shufflePlay,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        // Content list
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding - 16),
            children: [
              // Subfolders
              ..._subfolders.map((folder) => ListTile(
                leading: folder.coverArtUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: folder.coverArtUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.folder, size: 48, color: Colors.blue),
                        ),
                      )
                    : const Icon(Icons.folder, size: 48, color: Colors.blue),
                title: Text(
                  folder.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: folder.subtitle.isNotEmpty ? Text(folder.subtitle) : null,
                onTap: () => _openSubfolder(folder),
              )),
              if (_subfolders.isNotEmpty && _tracks.isNotEmpty)
                const Divider(),
              // Tracks
              ...List.generate(_tracks.length, (index) {
                final track = _tracks[index];
                return _FolderTrackTile(
                  track: track,
                  index: index,
                  onTap: () => _playTrack(track),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

/// Extracted track tile that uses Selector to avoid rebuilding on position updates.
class _FolderTrackTile extends StatelessWidget {
  final Track track;
  final int index;
  final VoidCallback onTap;

  const _FolderTrackTile({
    required this.track,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, String?>(
      selector: (_, ps) => ps.currentTrack?.id,
      builder: (context, currentTrackId, _) {
        final isCurrentTrack = currentTrackId == track.id;

        return ListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: isCurrentTrack ? Colors.blue : Colors.grey,
                    fontWeight: isCurrentTrack ? FontWeight.bold : null,
                  ),
                ),
              ),
              if (track.coverArtUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: track.coverArtUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(Icons.music_note, size: 48),
                  ),
                )
              else
                const Icon(Icons.music_note, size: 48),
            ],
          ),
          title: Text(
            track.title,
            style: TextStyle(
              fontWeight: isCurrentTrack ? FontWeight.bold : null,
              color: isCurrentTrack ? Colors.blue : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${track.artist ?? ''} ${track.formattedDuration}'.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isCurrentTrack
              ? const Icon(Icons.equalizer, color: Colors.blue)
              : null,
          onTap: onTap,
        );
      },
    );
  }
}
