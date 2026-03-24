import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../models/folder.dart';
import '../services/auth_service.dart';
import '../services/subsonic_api_service.dart';
import '../services/audio_player_service.dart';
import '../services/library_scanner.dart';
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
  String _searchQuery = '';
  Timer? _debounceTimer;

  // Search results (only used when searching)
  List<Folder> _searchFolders = [];
  List<Track> _searchTracks = [];
  bool _isSearching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    // Trigger library scan on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryScanner>().scan();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  SubsonicApiService? get _api => context.read<AuthService>().apiService;

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      setState(() {
        _searchFolders = [];
        _searchTracks = [];
        _isSearching = false;
        _searchError = null;
      });
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
      _isSearching = true;
      _searchError = null;
    });

    try {
      final result = await api.search3(query);

      if (!mounted) return;
      if (_searchQuery != query) return;

      setState(() {
        _searchFolders = result.albums;
        _searchTracks = result.songs;
        _isSearching = false;
      });
    } on SubsonicApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e.message;
        _isSearching = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final authService = context.read<AuthService>();
    await authService.logout();
  }

  void _playTrack(Track track, List<Track> playlist) {
    final playerService = context.read<AudioPlayerService>();
    final trackIndex = playlist.indexOf(track);
    playerService.playPlaylist(playlist, trackIndex);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  Future<void> _playFolder(Folder folder) async {
    final scanner = context.read<LibraryScanner>();
    final playerService = context.read<AudioPlayerService>();
    final messenger = ScaffoldMessenger.of(context);

    if (folder.id == null) return;

    final tracks = scanner.getAllTracksInFolder(folder.id!);

    if (tracks.isNotEmpty) {
      if (!playerService.isShuffleEnabled) {
        playerService.toggleShuffle();
      }
      playerService.playPlaylist(tracks, -1);
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
  }

  void _openFolder(Folder folder) {
    if (folder.id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(
          folderId: folder.id!,
          folderName: folder.displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final scanner = context.watch<LibraryScanner>();
    final horizontalPadding = Responsive.getHorizontalPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Welcome, ${authService.currentUser?.username ?? "User"}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (scanner.isScanning)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (scanner.hasScanned && !scanner.isScanning)
                      Text(
                        '${scanner.allTracks.length} tracks',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Content
              Expanded(
                child: _searchQuery.isNotEmpty
                    ? _buildSearchResults()
                    : _buildFolderBrowser(scanner),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the folder browser from the scanned library.
  Widget _buildFolderBrowser(LibraryScanner scanner) {
    final horizontalPadding = Responsive.getHorizontalPadding(context);
    final isDesktop = Responsive.isDesktopOrLarger(context);
    final gridColumns = Responsive.getGridColumns(context);

    if (scanner.isScanning && !scanner.hasScanned) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning library...'),
          ],
        ),
      );
    }

    if (scanner.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(scanner.error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => scanner.rescan(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final folders = scanner.getTopLevelFolders();
    final rootTracks = scanner.getRootTracks();

    if (folders.isEmpty && rootTracks.isEmpty) {
      return const Center(child: Text('No content found'));
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      children: [
        // Root-level tracks (songs not in any folder)
        if (rootTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Songs (${rootTracks.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    final playerService = context.read<AudioPlayerService>();
                    if (!playerService.isShuffleEnabled) {
                      playerService.toggleShuffle();
                    }
                    playerService.playPlaylist(rootTracks, -1);
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
          ...rootTracks.map((track) => _TrackTile(
            track: track,
            onTap: () => _playTrack(track, rootTracks),
          )),
          const Divider(height: 32),
        ],

        // Folders section
        if (folders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Folders (${folders.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
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
              itemCount: folders.length,
              itemBuilder: (context, index) => _buildFolderCard(folders[index]),
            )
          else
            ...folders.map((folder) => _buildFolderTile(folder)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  /// Build search results view.
  Widget _buildSearchResults() {
    final horizontalPadding = Responsive.getHorizontalPadding(context);

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_searchError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _performSearch(_searchQuery),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_searchFolders.isEmpty && _searchTracks.isEmpty) {
      return const Center(child: Text('No results found'));
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      children: [
        if (_searchTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Songs (${_searchTracks.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    final playerService = context.read<AudioPlayerService>();
                    if (!playerService.isShuffleEnabled) {
                      playerService.toggleShuffle();
                    }
                    playerService.playPlaylist(_searchTracks, -1);
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
          ..._searchTracks.map((track) => _TrackTile(
            track: track,
            onTap: () => _playTrack(track, _searchTracks),
          )),
          const Divider(height: 32),
        ],
        if (_searchFolders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Albums (${_searchFolders.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ..._searchFolders.map((folder) => _buildFolderTile(folder)),
        ],
        const SizedBox(height: 16),
      ],
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
        folder.displayName,
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
                folder.displayName,
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
          subtitle: Text(track.formattedDuration),
          trailing: isCurrentTrack
              ? const Icon(Icons.equalizer, color: Colors.blue)
              : null,
          onTap: onTap,
        );
      },
    );
  }
}
