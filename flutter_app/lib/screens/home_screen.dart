import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../models/folder.dart';
import '../services/auth_service.dart';
import '../services/subsonic_api_service.dart';
import '../services/audio_player_service.dart';
import '../utils/responsive.dart';
import 'player_screen.dart';
import 'folder_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  List<Folder> _folders = [];
  List<Folder> _recentAlbums = [];
  List<Track> _rootTracks = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
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
    List<Folder> recentAlbums = [];
    String? error;

    try {
      // Load folders and recently added albums in parallel
      final results = await Future.wait([
        api.getFolders(),
        api.getAlbumList2(type: 'newest', size: 10),
      ]);
      folders = results[0] as List<Folder>;
      recentAlbums = results[1] as List<Folder>;
    } catch (e) {
      debugPrint('Failed to load data: $e');
      error = 'Failed to load folders';
      // Try loading just folders if album list fails
      try {
        folders = await api.getFolders();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _folders = folders;
      _recentAlbums = recentAlbums;
      _rootTracks = [];
      _isLoading = false;
      _errorMessage = folders.isEmpty && recentAlbums.isEmpty ? error : null;
    });
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      _loadData();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    final api = _api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await api.search3(query);

      if (!mounted) return;
      // Verify query hasn't changed while we were waiting
      if (_searchQuery != query) return;

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
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text('Loading ${folder.folderPath}...'),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final tracks = await api.getAllTracksInDirectory(folder.id!);

      messenger.hideCurrentSnackBar();

      if (tracks.isNotEmpty) {
        playerService.playPlaylist(tracks, 0);
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayerScreen()),
          );
        }
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('No tracks found in this folder')),
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final horizontalPadding = Responsive.getHorizontalPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
        actions: [
          // Use Selector to only rebuild when currentTrack presence changes
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
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onSearchChanged,
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
      floatingActionButton: Selector<AudioPlayerService, ({bool hasTrack, bool isPlaying})>(
        selector: (_, ps) => (hasTrack: ps.currentTrack != null, isPlaying: ps.isPlaying),
        builder: (context, state, _) => state.hasTrack
            ? FloatingActionButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
                child: Icon(
                  state.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              )
            : const SizedBox.shrink(),
      ),
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

    if (_folders.isEmpty && _rootTracks.isEmpty && _recentAlbums.isEmpty) {
      return const Center(
        child: Text('No content found'),
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      children: [
        // Recently Added section (only in default view, not search)
        if (_recentAlbums.isNotEmpty && _searchQuery.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.new_releases, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text(
                  'Recently Added',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _recentAlbums.length,
              itemBuilder: (context, index) => _buildRecentAlbumCard(_recentAlbums[index]),
            ),
          ),
          const Divider(height: 24),
        ],

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
          ..._rootTracks.map((track) => _TrackTile(
            track: track,
            onTap: () => _playRootTrack(track),
          )),
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

  /// Horizontal scrolling card for recently added albums
  Widget _buildRecentAlbumCard(Folder album) {
    return SizedBox(
      width: 140,
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(right: 12),
        child: InkWell(
          onTap: () => _openFolder(album),
          onLongPress: () => _playFolder(album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: album.coverArtUrl != null
                    ? CachedNetworkImage(
                        imageUrl: album.coverArtUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Center(
                          child: Icon(Icons.album, size: 48, color: Colors.deepPurple),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.album, size: 48, color: Colors.deepPurple),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                child: Text(
                  album.folderPath,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
        ),
      ),
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
                  ? CachedNetworkImage(
                      imageUrl: folder.coverArtUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Center(
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

/// Extracted track tile widget that uses Selector to only rebuild when
/// the current track ID changes, not on every position update.
class _TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  const _TrackTile({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, String?>(
      selector: (_, ps) => ps.currentTrack?.id,
      builder: (context, currentTrackId, _) {
        final isCurrentTrack = currentTrackId == track.id;

        return ListTile(
          leading: track.coverArtUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: track.coverArtUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(
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
          onTap: onTap,
        );
      },
    );
  }
}
