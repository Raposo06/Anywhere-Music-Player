import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../models/folder.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
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

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final apiService = context.read<ApiService>();

    // Load folders and root tracks separately to handle partial failures
    List<Folder> folders = [];
    List<Track> rootTracks = [];
    String? error;

    try {
      folders = await apiService.getFolders();
      debugPrint('📁 Loaded ${folders.length} folders');
      for (var folder in folders) {
        debugPrint('  - "${folder.folderPath}" (${folder.trackCount} tracks)');
      }
    } catch (e) {
      debugPrint('Failed to load folders: $e');
      error = 'Failed to load folders';
    }

    try {
      rootTracks = await apiService.getRootTracks();
    } catch (e) {
      debugPrint('Failed to load root tracks: $e');
      // Don't overwrite folders error, root tracks are optional
    }

    if (!mounted) return;
    setState(() {
      _folders = folders;
      _rootTracks = rootTracks;
      _isLoading = false;
      _errorMessage = folders.isEmpty && rootTracks.isEmpty ? error : null;
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final folders = await apiService.searchFolders(query);

      if (!mounted) return;
      setState(() {
        _folders = folders;
        _rootTracks = []; // Clear root tracks during search
        _isLoading = false;
      });
    } on ApiException catch (e) {
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

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _playRootTrack(Track track) {
    final playerService = context.read<AudioPlayerService>();
    final trackIndex = _rootTracks.indexOf(track);
    playerService.playPlaylist(_rootTracks, trackIndex);

    // Navigate to player screen
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  Future<void> _playFolder(Folder folder) async {
    final apiService = context.read<ApiService>();
    final playerService = context.read<AudioPlayerService>();

    debugPrint('🎵 _playFolder called for: ${folder.folderPath}');

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loading ${folder.folderPath}...'),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      // Get all tracks in this folder and subfolders
      debugPrint('📡 Fetching tracks with parentFolder: ${folder.folderPath}');
      final tracks = await apiService.getTracks(parentFolder: folder.folderPath);
      debugPrint('✅ Received ${tracks.length} tracks from API');

      if (tracks.isNotEmpty) {
        playerService.playPlaylist(tracks, 0);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // Navigate to player screen
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
                    hintText: 'Search folders...',
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
        // Root tracks section (songs not in any folder)
        if (_rootTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Loose Tracks (${_rootTracks.length})',
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
                childAspectRatio: 1.2,
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
      subtitle: Text(track.formattedDuration),
      trailing: isCurrentTrack
          ? const Icon(Icons.equalizer, color: Colors.blue)
          : null,
      onTap: () => _playRootTrack(track),
    );
  }

  void _openFolder(Folder folder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(
          folderPath: folder.folderPath,
          folderName: folder.folderPath,
        ),
      ),
    );
  }

  Widget _buildFolderTile(Folder folder) {
    return ListTile(
      leading: const Icon(Icons.folder, size: 48, color: Colors.blue),
      title: Text(
        folder.folderPath,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      subtitle: Text('${folder.trackCount} track(s)'),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder, size: 64, color: Colors.blue),
              const SizedBox(height: 12),
              Text(
                folder.folderPath,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${folder.trackCount} track(s)',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_circle_fill, color: Colors.green),
                    iconSize: 32,
                    onPressed: () => _playFolder(folder),
                    tooltip: 'Play all',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
