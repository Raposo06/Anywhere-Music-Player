import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/folder.dart';
import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../services/auth_service.dart';
import '../../services/library_scanner.dart';
import '../../services/subsonic_api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/desktop/desktop_primitives.dart';
import '../../widgets/desktop/desktop_track_row.dart';
import 'desktop_folder_screen.dart';
import 'desktop_search_field.dart';
import 'desktop_shell.dart';

/// Library home: the folder grid, with search.
///
/// The desktop counterpart to [HomeScreen]. The browsing model is unchanged —
/// top-level folders from [LibraryScanner], with root-level tracks below —
/// only the presentation is: a grid of cover-art cards rather than a list.
class DesktopLibraryScreen extends StatefulWidget {
  const DesktopLibraryScreen({super.key});

  @override
  State<DesktopLibraryScreen> createState() => _DesktopLibraryScreenState();
}

class _DesktopLibraryScreenState extends State<DesktopLibraryScreen> {
  String _query = '';
  Timer? _debounce;

  List<Folder> _searchFolders = [];
  List<Track> _searchTracks = [];
  bool _isSearching = false;
  String? _searchError;

  LibraryScanner? _scannerForListener;

  @override
  void initState() {
    super.initState();
    // The shell kicks off the scan; this screen only watches for the soft
    // refresh errors that would otherwise be swallowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scanner = context.read<LibraryScanner>();
      _scannerForListener = scanner;
      scanner.addListener(_onScannerChanged);
    });
  }

  @override
  void dispose() {
    _scannerForListener?.removeListener(_onScannerChanged);
    _debounce?.cancel();
    super.dispose();
  }

  /// Surface [LibraryScanner.refreshError] as a snackbar when a background
  /// refresh fails while cached data is on screen. Clears the error on the
  /// scanner so it fires once per failure.
  void _onScannerChanged() {
    if (!mounted) return;
    final message = _scannerForListener?.refreshError;
    if (message == null) return;
    _scannerForListener!.clearRefreshError();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    setState(() => _query = query);

    if (query.isEmpty) {
      setState(() {
        _searchFolders = [];
        _searchTracks = [];
        _isSearching = false;
        _searchError = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    final SubsonicApiService? api = context.read<AuthService>().apiService;
    if (api == null) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final result = await api.search3(query);
      if (!mounted || _query != query) return;

      // Subsonic's search3 returns tracks with tag-based virtual paths
      // ("Artist/Album/..."), not real filesystem paths. Map each result back
      // to its canonical Track from the scanner (by id) so folderPath and
      // friends match what the rest of the app uses — otherwise opening a
      // result's folder lands on a path that doesn't exist. Folders come from
      // the local virtual tree for the same reason.
      final scanner = context.read<LibraryScanner>();
      final canonicalById = {for (final t in scanner.allTracks) t.id: t};

      setState(() {
        _searchFolders = scanner.searchFolders(query);
        _searchTracks = result.songs
            .map((t) => canonicalById[t.id] ?? t)
            .toList();
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

  void _openFolder(Folder folder) {
    final id = folder.id ?? folder.folderPath;
    if (id.isEmpty) return;
    Navigator.of(context).push(
      DesktopFolderScreen.route(folderPath: id, folderName: folder.displayName),
    );
  }

  void _playFolder(Folder folder) {
    final id = folder.id ?? folder.folderPath;
    if (id.isEmpty) return;
    final tracks = context.read<LibraryScanner>().getAllTracksInFolder(id);
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks found in this folder')),
      );
      return;
    }
    context.read<AudioPlayerService>().play(tracks);
  }

  void _playTrack(Track track, List<Track> playlist) {
    final player = context.read<AudioPlayerService>();
    // Already the current track — don't restart it, just show it.
    if (player.currentTrack?.id != track.id) {
      player.play(playlist, from: playlist.indexOf(track));
    }
    DesktopPlayerLauncher.openPlayer(context);
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<LibraryScanner>();

    return ColoredBox(
      color: AppColors.win,
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              subtitle: _subtitleFor(scanner),
              query: _query,
              onQueryChanged: _onQueryChanged,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _query.isEmpty
                  ? _buildBrowser(scanner)
                  : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(LibraryScanner scanner) {
    if (!scanner.hasInitialData) {
      return scanner.isScanning ? 'Scanning library…' : '';
    }
    final folders = scanner.getTopLevelFolders().length;
    final tracks = scanner.allTracks.length;
    return '$folders folders · ${_thousands(tracks)} tracks';
  }

  Widget _buildBrowser(LibraryScanner scanner) {
    if (scanner.isScanning && !scanner.hasInitialData) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning library…', style: TextStyle(color: AppColors.muted)),
          ],
        ),
      );
    }

    if (scanner.error case final error?) {
      return DesktopErrorState(message: error, onRetry: scanner.rescan);
    }

    final folders = scanner.getTopLevelFolders();
    final rootTracks = scanner.getRootTracks();

    if (folders.isEmpty && rootTracks.isEmpty) {
      return const Center(
        child: Text(
          'No content found',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (folders.isNotEmpty)
          _FolderGrid(
            folders: folders,
            onOpen: _openFolder,
            onPlay: _playFolder,
          ),
        if (rootTracks.isNotEmpty) ...[
          const SizedBox(height: 28),
          const SectionLabel('Tracks'),
          const SizedBox(height: 6),
          for (final (index, track) in rootTracks.indexed)
            DesktopTrackRow(
              track: track,
              number: index + 1,
              onTap: () => _playTrack(track, rootTracks),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError case final error?) {
      return DesktopErrorState(
        message: error,
        onRetry: () => _search(_query),
      );
    }
    if (_searchFolders.isEmpty && _searchTracks.isEmpty) {
      return const Center(
        child: Text(
          'No results found',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (_searchFolders.isNotEmpty) ...[
          const SectionLabel('Folders'),
          const SizedBox(height: 6),
          _FolderGrid(
            folders: _searchFolders,
            onOpen: _openFolder,
            onPlay: _playFolder,
          ),
          const SizedBox(height: 28),
        ],
        if (_searchTracks.isNotEmpty) ...[
          const SectionLabel('Tracks'),
          const SizedBox(height: 6),
          for (final (index, track) in _searchTracks.indexed)
            DesktopTrackRow(
              track: track,
              number: index + 1,
              onTap: () => _playTrack(track, _searchTracks),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Groups digits so a five-figure library reads as "4,260 tracks" like the
/// design, without pulling in `intl` for one call site.
String _thousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _Header extends StatelessWidget {
  final String subtitle;
  final String query;
  final ValueChanged<String> onQueryChanged;

  const _Header({
    required this.subtitle,
    required this.query,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Library', style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 24),
        DesktopSearchField(onChanged: onQueryChanged),
      ],
    );
  }
}

/// The three-across grid of folder cards.
class _FolderGrid extends StatelessWidget {
  final List<Folder> folders;
  final ValueChanged<Folder> onOpen;
  final ValueChanged<Folder> onPlay;

  const _FolderGrid({
    required this.folders,
    required this.onOpen,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      // The design fixes three columns at its 1240px reference width. A max
      // extent (rather than a fixed count) holds the card at roughly that
      // size and adds columns as the window widens, instead of stretching
      // three covers across an ultrawide monitor.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 0.86,
      ),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        return _FolderCard(
          folder: folder,
          onOpen: () => onOpen(folder),
          onPlay: () => onPlay(folder),
        );
      },
    );
  }
}

/// A folder as a [HoverCoverCard] — just the folder-specific text and icon,
/// the card itself is shared with the playlists grid.
class _FolderCard extends StatelessWidget {
  final Folder folder;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  const _FolderCard({
    required this.folder,
    required this.onOpen,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCoverCard(
      source: folder,
      fallbackIcon: Icons.folder_outlined,
      title: folder.displayName,
      subtitle: folder.subtitle,
      playTooltip: 'Play all tracks in this folder',
      onOpen: onOpen,
      onPlay: onPlay,
    );
  }
}
