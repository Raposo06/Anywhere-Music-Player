import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../models/folder.dart';
import '../services/auth_service.dart';
import '../services/subsonic_api_service.dart';
import '../services/audio_player_service.dart';
import '../services/library_scanner.dart';
import '../utils/responsive.dart';
import '../widgets/centred_message.dart';
import '../widgets/cover_art.dart';
import '../widgets/play_actions.dart';
import '../widgets/track_tile.dart';
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

  LibraryScanner? _scannerForListener;

  @override
  void initState() {
    super.initState();
    // Trigger library scan on first load and watch for soft refresh errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scanner = context.read<LibraryScanner>();
      _scannerForListener = scanner;
      scanner.addListener(_onScannerChanged);
      scanner.scan();
    });
  }

  @override
  void dispose() {
    _scannerForListener?.removeListener(_onScannerChanged);
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Surface [LibraryScanner.refreshError] as a snackbar when a background
  /// refresh fails while cached data is on screen. Clears the error on the
  /// scanner so it fires once per failure.
  void _onScannerChanged() {
    if (!mounted) return;
    final scanner = _scannerForListener;
    if (scanner == null) return;

    final message = scanner.refreshError;
    if (message == null) return;
    scanner.clearRefreshError();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ));
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

      // Subsonic's search3 returns tracks with tag-based virtual paths
      // ("Artist/Album/..."), not real filesystem paths. Map each search
      // result to its canonical Track from the library scanner (by id) so
      // folderPath, folderName etc. match what the rest of the app uses —
      // otherwise tapping a result and opening its folder lands on a
      // non-existent virtual path.
      //
      // Folders come from the local virtual tree (not search3's tag-based
      // "albums") so tapping a result opens a real folder, and the user
      // doesn't see album entries that don't map to anything browsable.
      final scanner = context.read<LibraryScanner>();
      final canonicalById = {for (final t in scanner.allTracks) t.id: t};
      final canonicalSongs = result.songs
          .map((t) => canonicalById[t.id] ?? t)
          .toList();

      setState(() {
        _searchFolders = scanner.searchFolders(query);
        _searchTracks = canonicalSongs;
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
    // Read all three before the first await — using `context` after an
    // await needs a `mounted` guard, and these are stable Provider
    // singletons for this widget's lifetime, so reading them upfront and
    // holding local references avoids the guard entirely.
    final player = context.read<AudioPlayerService>();
    final scanner = context.read<LibraryScanner>();
    final auth = context.read<AuthService>();
    await player.stop();
    await scanner.resetAndClearCache();
    await auth.logout();
  }

  Future<void> _playFolder(Folder folder) async {
    final scanner = context.read<LibraryScanner>();
    final messenger = ScaffoldMessenger.of(context);

    if (folder.id == null) return;

    final tracks = scanner.getAllTracksInFolder(folder.id!);

    if (tracks.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No tracks found in this folder')),
      );
      return;
    }
    if (mounted) playAll(context, tracks, shuffled: true);
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
                    onPressed: () => openNowPlaying(context),
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
                    if (scanner.hasInitialData)
                      Text(
                        '${scanner.allTracks.length} tracks',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13),
                      ),
                    if (scanner.isScanning) ...[
                      if (scanner.hasInitialData) const SizedBox(width: 8),
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
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

    if (scanner.isScanning && !scanner.hasInitialData) {
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
      return CentredMessage(
        icon: Icons.error_outline,
        title: scanner.error!,
        action: FilledButton(
          onPressed: () => scanner.rescan(),
          child: const Text('Retry'),
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
                Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Songs (${rootTracks.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => playAll(context, rootTracks, shuffled: true),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Play All'),
                ),
              ],
            ),
          ),
          ...rootTracks.map((track) => TrackTile(
            track: track,
            onTap: () => playFromList(context, track, rootTracks),
          )),
          const Divider(height: 32),
        ],

        // Folders section
        if (folders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
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
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 250,
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
      return CentredMessage(
        icon: Icons.error_outline,
        title: _searchError!,
        action: FilledButton(
          onPressed: () => _performSearch(_searchQuery),
          child: const Text('Retry'),
        ),
      );
    }

    if (_searchFolders.isEmpty && _searchTracks.isEmpty) {
      return const Center(child: Text('No results found'));
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      children: [
        if (_searchFolders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Folders (${_searchFolders.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ..._searchFolders.map((folder) => _buildFolderTile(folder)),
          const Divider(height: 32),
        ],
        if (_searchTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Songs (${_searchTracks.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      playAll(context, _searchTracks, shuffled: true),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Play All'),
                ),
              ],
            ),
          ),
          ..._searchTracks.map((track) => TrackTile(
            track: track,
            onTap: () => playFromList(context, track, _searchTracks),
          )),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFolderTile(Folder folder) {
    return ListTile(
      leading: CoverArt(
        folder,
        size: 48,
        fallbackIcon: Icons.folder,
        fallbackIconColor: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        folder.displayName,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      subtitle: folder.subtitle.isNotEmpty ? Text(folder.subtitle) : null,
      trailing: IconButton(
        icon: Icon(Icons.play_circle_fill,
            size: 36, color: Theme.of(context).colorScheme.primary),
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
              // Stable card-sized request (DPI-aware but NOT tied to the live
              // card width) so resizing the window doesn't change the URL
              // and force a re-download. radius: 0 — the Card itself already
              // clips (clipBehavior: Clip.antiAlias above).
              child: CoverArt(
                folder,
                size: 384,
                expand: true,
                radius: 0,
                fallbackIcon: Icons.folder,
                fallbackIconColor: Theme.of(context).colorScheme.primary,
                fallbackIconSize: 64,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.play_circle_fill,
                      color: Theme.of(context).colorScheme.primary),
                  iconSize: 36,
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

// Track rows are TrackTile (lib/widgets/track_tile.dart).
