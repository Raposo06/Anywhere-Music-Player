import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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

  // Drives "follow the playing track": scroll the list to the current song.
  final ItemScrollController _itemScrollController = ItemScrollController();
  // Last track id we scrolled to, so we only follow on an actual change.
  String? _followedTrackId;

  @override
  void initState() {
    super.initState();
    _loadContents();
    context.read<AudioPlayerService>().addListener(_followCurrentTrack);
  }

  @override
  void dispose() {
    _searchController.dispose();
    try {
      context.read<AudioPlayerService>().removeListener(_followCurrentTrack);
    } catch (_) {}
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _followCurrentTrack());
  }

  /// Number of non-track rows that precede the track rows in the list
  /// (subfolders + the divider between them and the tracks). Used to map a
  /// track's index to its row position for scroll-to.
  int get _leadingRowCount {
    final showSubfolders = !_isSearching && _subfolders.isNotEmpty;
    if (!showSubfolders) return 0;
    return _subfolders.length + (_tracks.isNotEmpty ? 1 : 0);
  }

  /// Scroll the list so the currently-playing track is visible. Only acts when
  /// the playing track id changes (and on open), so manual scrolling between
  /// songs is never interrupted. No-op if the track isn't in the current list.
  void _followCurrentTrack() {
    if (!mounted) return;
    final id = context.read<AudioPlayerService>().currentTrack?.id;
    if (id == null) {
      _followedTrackId = null;
      return;
    }
    if (id == _followedTrackId) return;
    final trackIndex = _filteredTracks.indexWhere((t) => t.id == id);
    if (trackIndex < 0) return; // not in this list — leave _followedTrackId unset
    if (!_itemScrollController.isAttached) return; // retried on next change/open
    _followedTrackId = id;
    _itemScrollController.scrollTo(
      index: _leadingRowCount + trackIndex,
      alignment: 0.3,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
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

  /// Open a folder by its full virtual path. Used by the breadcrumb — always
  /// pushes a fresh screen rather than trying to pop back to an existing one
  /// in the stack, because the user may have arrived at the current folder
  /// via a path that doesn't include the breadcrumb target (e.g. from search
  /// or a deep-link). The back button will still unwind through real history.
  ///
  /// Exception: if [fullPath] is the auto-flattened root (e.g. the lone
  /// top-level "Animes" folder whose children are surfaced directly on the
  /// home screen), we pop the navigator back to home — opening a folder
  /// screen for that path would just duplicate the home screen.
  void _openFolderByPath(String fullPath, String displayName) {
    final scanner = context.read<LibraryScanner>();
    if (scanner.isFlattenedRoot(fullPath)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(
          folderId: fullPath,
          folderName: displayName,
        ),
      ),
    );
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Build a clickable breadcrumb for the current folder path. Always shows
  /// a home shortcut on the left; the path segments follow when the folder
  /// has parents. Returns null only when there's nothing useful to show
  /// (single-segment top-level folder — back button already does the job).
  Widget? _buildBreadcrumb() {
    final segments = widget.folderId.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= 1) return null;

    final theme = Theme.of(context);
    final scanner = context.read<LibraryScanner>();
    final linkColor = theme.colorScheme.primary;
    final mutedColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final children = <Widget>[
      _BreadcrumbCrumb(
        icon: Icons.home_rounded,
        color: linkColor,
        onTap: _goHome,
        tooltip: 'Home',
      ),
    ];

    var accumulated = '';
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      accumulated = accumulated.isEmpty ? segment : '$accumulated/$segment';
      final isLast = i == segments.length - 1;
      final pathForSegment = accumulated;

      // The auto-flattened root (e.g. "Animes") is already represented by
      // the home icon — rendering it again as a separate crumb would just
      // be two buttons pointing at the same destination.
      if (scanner.isFlattenedRoot(pathForSegment)) continue;

      children.add(_BreadcrumbSeparator(color: mutedColor));

      if (isLast) {
        children.add(_BreadcrumbCrumb(
          label: segment,
          color: theme.colorScheme.onSurface,
          bold: true,
          onTap: null, // current folder — non-interactive
        ));
      } else {
        children.add(_BreadcrumbCrumb(
          label: segment,
          color: linkColor,
          onTap: () => _openFolderByPath(pathForSegment, segment),
        ));
      }
    }

    final horizontalPadding = Responsive.getHorizontalPadding(context);
    final maxWidth = Responsive.getContentMaxWidth(context);

    // Background banner spans the full window width; the row of crumbs
    // inside is centered/constrained to align with the rest of the
    // page content (so the home icon sits flush under the AppBar title
    // rather than floating in the left margin on wide screens).
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface.withValues(alpha: 0.4),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 10,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? double.infinity,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
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
      body: _buildBody(),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _buildBody() {
    final horizontalPadding = Responsive.getHorizontalPadding(context);
    final maxWidth = Responsive.getContentMaxWidth(context);
    final visibleTracks = _filteredTracks;
    final showSubfolders = !_isSearching && _subfolders.isNotEmpty;

    if (_tracks.isEmpty && _subfolders.isEmpty) {
      return const Center(child: Text('No content found'));
    }

    if (_isSearching && visibleTracks.isEmpty) {
      return const Center(child: Text('No tracks match your search'));
    }

    final breadcrumb = _isSearching ? null : _buildBreadcrumb();

    // Breadcrumb spans the full window width (background banner-style),
    // while the rest of the content remains centered + constrained.
    return Column(
      children: [
        if (breadcrumb != null) breadcrumb,
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth ?? double.infinity,
              ),
              child: _buildScrollableContent(
                horizontalPadding: horizontalPadding,
                visibleTracks: visibleTracks,
                showSubfolders: showSubfolders,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScrollableContent({
    required double horizontalPadding,
    required List<Track> visibleTracks,
    required bool showSubfolders,
  }) {
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
        // Content list. ScrollablePositionedList (instead of a plain ListView)
        // so we can scroll to the playing track by index — see
        // _followCurrentTrack. Rows are: [subfolders][divider][tracks].
        Expanded(
          child: ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding - 16),
            itemCount: _leadingRowCount + visibleTracks.length,
            itemBuilder: (context, i) {
              // Subfolders (hidden during search).
              if (showSubfolders && i < _subfolders.length) {
                final folder = _subfolders[i];
                return ListTile(
                  leading: folder.coverArtUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: folder.coverUrl(
                                size: (48 *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round())!,
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
                );
              }
              // Divider between subfolders and tracks.
              if (showSubfolders && _tracks.isNotEmpty && i == _subfolders.length) {
                return const Divider();
              }
              // Tracks.
              final index = i - _leadingRowCount;
              final track = visibleTracks[index];
              return _FolderTrackTile(
                track: track,
                index: _isSearching ? _tracks.indexOf(track) : index,
                onTap: () {
                  final playerService = context.read<AudioPlayerService>();
                  // If this track is already the current one, don't restart it
                  // — just open the player and let it keep playing.
                  if (playerService.currentTrack?.id != track.id) {
                    // Always play from the full folder list so playback
                    // continues through tracks not matched by the search.
                    playerService.playPlaylist(_tracks, _tracks.indexOf(track));
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
              );
            },
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
                    imageUrl: track.coverUrl(
                        size: (48 * MediaQuery.devicePixelRatioOf(context))
                            .round())!,
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

/// One segment of the breadcrumb — either a clickable parent link or the
/// non-interactive current-folder label. Renders as a tappable chip with
/// ripple feedback, matching the app's interaction style.
class _BreadcrumbCrumb extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final Color color;
  final bool bold;
  final VoidCallback? onTap;
  final String? tooltip;

  const _BreadcrumbCrumb({
    this.label,
    this.icon,
    required this.color,
    this.bold = false,
    this.onTap,
    this.tooltip,
  }) : assert(label != null || icon != null,
            'Crumb must have either a label or an icon');

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: icon != null
          ? Icon(icon, size: 22, color: color)
          : Text(
              label!,
              style: TextStyle(
                color: color,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                fontSize: 17,
              ),
            ),
    );

    if (onTap == null) {
      // Current folder — flat, no hover, no ripple, just typography.
      return content;
    }

    final clickable = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: color.withValues(alpha: 0.08),
        splashColor: color.withValues(alpha: 0.16),
        child: content,
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: clickable);
    }
    return clickable;
  }
}

/// Visual separator between breadcrumb crumbs. Pulled out so the styling
/// stays consistent and the build method above stays compact.
class _BreadcrumbSeparator extends StatelessWidget {
  final Color color;

  const _BreadcrumbSeparator({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(Icons.chevron_right_rounded, size: 20, color: color),
    );
  }
}
