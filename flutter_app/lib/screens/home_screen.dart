import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../models/folder.dart';
import '../services/auth_service.dart';
import '../services/subsonic_api_service.dart';
import '../services/audio_player_service.dart';
import '../utils/responsive.dart';
import 'player_screen.dart';
import 'login_screen.dart';
import 'folder_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  List<Folder> _folders = [];
  List<Track> _rootTracks = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SubsonicApiService? get _api => context.read<AuthService>().apiService;

  Future<void> _loadData() async {
    if (!mounted) return;
    final api = _api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    List<Folder> folders = [];
    String? error;

    try {
      folders = await api.getFolders();
    } catch (e) {
      debugPrint('Failed to load folders: $e');
      error = 'Failed to load folders';
    }

    if (!mounted) return;
    setState(() {
      _folders = folders;
      _rootTracks = [];
      _isLoading = false;
      _errorMessage = folders.isEmpty ? error : null;
    });
  }

  Future<void> _handleSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      _loadData();
      return;
    }

    final api = _api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await api.search3(query);

      if (!mounted) return;
      setState(() {
        _folders = result.albums;
        _rootTracks = result.songs;
        _isLoading = false;
      });
    } on SubsonicApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final authService = context.read<AuthService>();
    await authService.logout();
  }

  void _playRootTrack(Track track) {
    final playerService = context.read<AudioPlayerService>();
    final trackIndex = _rootTracks.indexOf(track);
    playerService.playPlaylist(_rootTracks, trackIndex);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  Future<void> _playFolder(Folder folder) async {
    final api = _api;
    if (api == null || folder.id == null) return;
    final playerService = context.read<AudioPlayerService>();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loading ${folder.folderPath}...'),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final tracks = await api.getAllTracksInDirectory(folder.id!);

      if (tracks.isNotEmpty) {
        playerService.playPlaylist(tracks, 0);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayerScreen()),
          );
        }
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tracks found in this folder')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final playerService = context.watch<AudioPlayerService>();
    final horizontalPadding = Responsive.getHorizontalPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
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
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.getContentMaxWidth(context) ?? double.infinity,
          ),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: EdgeInsets.all(horizontalPadding),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _handleSearch('');
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _handleSearch,
                ),
              ),

              // User info
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Welcome, ${authService.currentUser?.username ?? "User"}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Content
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
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

  Widget _buildContent() {
    final horizontalPadding = Responsive.getHorizontalPadding(context);
    final isDesktop = Responsive.isDesktopOrLarger(context);
    final gridColumns = Responsive.getGridColumns(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_folders.isEmpty && _rootTracks.isEmpty) {
      return const Center(
        child: Text('No content found'),
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      children: [
        // Search result tracks
        if (_rootTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Songs (${_rootTracks.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    final playerService = context.read<AudioPlayerService>();
                    playerService.playPlaylist(_rootTracks, 0);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlayerScreen()),
                    );
                  },
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Play All'),
                ),
              ],
            ),
          ),
          ..._rootTracks.map((track) => _buildTrackTile(track)),
          const Divider(height: 32),
        ],

        // Folders section
        if (_folders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Folders (${_folders.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Use grid on desktop, list on mobile
          if (isDesktop)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridColumns,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: _folders.length,
              itemBuilder: (context, index) => _buildFolderCard(_folders[index]),
            )
          else
            ..._folders.map((folder) => _buildFolderTile(folder)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTrackTile(Track track) {
    final playerService = context.watch<AudioPlayerService>();
    final isCurrentTrack = playerService.currentTrack?.id == track.id;

    return ListTile(
      leading: track.coverArtUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                track.coverArtUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.music_note,
                  size: 48,
                ),
              ),
            )
          : const Icon(Icons.music_note, size: 48),
      title: Text(
        track.title,
        style: TextStyle(
          fontWeight: isCurrentTrack ? FontWeight.bold : null,
          color: isCurrentTrack ? Colors.blue : null,
        ),
      ),
      subtitle: Text(track.artist ?? track.formattedDuration),
      trailing: isCurrentTrack
          ? const Icon(Icons.equalizer, color: Colors.blue)
          : null,
      onTap: () => _playRootTrack(track),
    );
  }

  void _openFolder(Folder folder) {
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

  Widget _buildFolderTile(Folder folder) {
    return ListTile(
      leading: folder.coverArtUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                folder.coverArtUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.folder, size: 48, color: Colors.blue),
              ),
            )
          : const Icon(Icons.folder, size: 48, color: Colors.blue),
      title: Text(
        folder.folderPath,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      subtitle: folder.subtitle.isNotEmpty ? Text(folder.subtitle) : null,
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_fill, size: 36, color: Colors.green),
        onPressed: () => _playFolder(folder),
        tooltip: 'Play all tracks in this folder',
      ),
      onTap: () => _openFolder(folder),
    );
  }

  /// Card-style folder widget for grid layout on desktop
  Widget _buildFolderCard(Folder folder) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openFolder(folder),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: folder.coverArtUrl != null
                  ? Image.network(
                      folder.coverArtUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.folder, size: 64, color: Colors.blue),
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.folder, size: 64, color: Colors.blue),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                folder.folderPath,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (folder.subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  folder.subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_circle_fill, color: Colors.green),
                  iconSize: 28,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  onPressed: () => _playFolder(folder),
                  tooltip: 'Play all',
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
