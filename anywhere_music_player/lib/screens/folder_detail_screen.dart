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
  int _totalTrackCount = 0;

  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadContents() {
    final scanner = context.read<LibraryScanner>();
    final contents = scanner.getFolderContents(widget.folderId);
    final allTracks = scanner.getAllTracksInFolder(widget.folderId);
    setState(() {
      _subfolders = contents.folders;
      _tracks = contents.tracks;
      _totalTrackCount = allTracks.length;
    });
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
      playerService.toggleShuffle();
    }
    playerService.playPlaylist(allTracks, -1);

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

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
    if (_isSearching) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchController.selection =
          TextSelection.fromPosition(TextPosition(offset: _searchController.text.length)));
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
  }

  List<Track> get _filteredTracks {
    if (_searchQuery.isEmpty) return _tracks;
    final q = _searchQuery.toLowerCase();
    return _tracks.where((t) => t.title.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search tracks...',
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : Text(widget.folderName),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
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
    final visibleTracks = _filteredTracks;
    final showSubfolders = !_isSearching && _subfolders.isNotEmpty;

    if (_tracks.isEmpty && _subfolders.isEmpty) {
      return const Center(child: Text('No content found'));
    }

    if (_isSearching && visibleTracks.isEmpty) {
      return const Center(child: Text('No tracks match your search'));
    }

    return Column(
      children: [
        // Header with play buttons
        if (!_isSearching && _totalTrackCount > 0)
          Container(
            padding: EdgeInsets.all(horizontalPadding),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_totalTrackCount track(s)',
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
        if (_isSearching && _searchQuery.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${visibleTracks.length} result(s)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        const Divider(height: 1),
        // Content list
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding - 16),
            children: [
              // Subfolders (hidden during search)
              if (showSubfolders)
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
              if (showSubfolders && _tracks.isNotEmpty)
                const Divider(),
              // Tracks
              ...List.generate(visibleTracks.length, (index) {
                final track = visibleTracks[index];
                return _FolderTrackTile(
                  track: track,
                  index: _isSearching ? _tracks.indexOf(track) : index,
                  onTap: () {
                    final playerService = context.read<AudioPlayerService>();
                    // Always play from the full folder list so playback
                    // continues through tracks not matched by the search.
                    playerService.playPlaylist(_tracks, _tracks.indexOf(track));
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlayerScreen()),
                    );
                  },
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

        return Dismissible(
          key: ValueKey('folder-$index-${track.id}'),
          direction: DismissDirection.startToEnd,
          background: Container(
            color: Colors.green.shade600,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.queue_music, color: Colors.white),
                SizedBox(width: 8),
                Text('Add to queue',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            final ps = context.read<AudioPlayerService>();
            final messenger = ScaffoldMessenger.of(context);
            final willQueue = ps.currentTrack != null;
            await ps.addToQueue(track);
            if (willQueue) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('Added to queue: ${track.title}'),
                  duration: const Duration(seconds: 2),
                ));
            }
            return false;
          },
          child: ListTile(
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
            track.formattedDuration,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isCurrentTrack
              ? const Icon(Icons.equalizer, color: Colors.blue)
              : null,
          onTap: onTap,
          ),
        );
      },
    );
  }
}
