import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../models/folder.dart';
import '../services/auth_service.dart';
import '../services/subsonic_api_service.dart';
import '../services/audio_player_service.dart';
import '../utils/responsive.dart';
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
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  SubsonicApiService? get _api => context.read<AuthService>().apiService;

  Future<void> _loadContents() async {
    if (!mounted) return;
    final api = _api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final contents = await api.getDirectoryContents(widget.folderId);

      if (!mounted) return;
      setState(() {
        _tracks = contents.tracks;
        _subfolders = contents.folders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load contents: $e';
        _isLoading = false;
      });
    }
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
    if (_tracks.isEmpty) return;
    final playerService = context.read<AudioPlayerService>();
    playerService.playPlaylist(_tracks, 0);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _shufflePlay() {
    if (_tracks.isEmpty) return;
    final playerService = context.read<AudioPlayerService>();
    if (!playerService.isShuffleEnabled) {
      playerService.toggleShuffle();
    }
    playerService.playPlaylist(_tracks, 0);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _openSubfolder(Folder folder) {
    if (folder.id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(
          folderId: folder.id!,
          folderName: folder.folderPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<AudioPlayerService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folderName),
        actions: [
          if (playerService.currentTrack != null)
            IconButton(
              icon: const Icon(Icons.music_note),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                );
              },
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
      floatingActionButton: playerService.currentTrack != null
          ? FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                );
              },
              child: Icon(
                playerService.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    final horizontalPadding = Responsive.getHorizontalPadding(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadContents,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

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
                leading: const Icon(Icons.folder, size: 48, color: Colors.blue),
                title: Text(
                  folder.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${folder.trackCount} item(s)'),
                onTap: () => _openSubfolder(folder),
              )),
              if (_subfolders.isNotEmpty && _tracks.isNotEmpty)
                const Divider(),
              // Tracks
              ...List.generate(_tracks.length, (index) {
                final track = _tracks[index];
                return _buildTrackTile(track, index);
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrackTile(Track track, int index) {
    final playerService = context.watch<AudioPlayerService>();
    final isCurrentTrack = playerService.currentTrack?.id == track.id;

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
              child: Image.network(
                track.coverArtUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 48),
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
      onTap: () => _playTrack(track),
    );
  }
}
