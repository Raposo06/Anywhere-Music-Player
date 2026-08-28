import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../models/folder.dart';
import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../services/library_scanner.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/desktop/desktop_primitives.dart';
import '../../widgets/desktop/desktop_track_row.dart';
import 'desktop_search_field.dart';

/// A folder's contents: subfolders ("Albums") above its own tracks.
///
/// The desktop counterpart to [FolderDetailScreen]. Same data and the same
/// recursive Play All / Shuffle semantics; the presentation gains a
/// breadcrumb trail and splits subfolders and tracks under labelled sections.
class DesktopFolderScreen extends StatefulWidget {
  final String folderPath;
  final String folderName;

  const DesktopFolderScreen({
    super.key,
    required this.folderPath,
    required this.folderName,
  });

  /// The route for this screen. The name carries the folder title so the
  /// shell's navigator observer can put it in the window chrome without the
  /// screen having to reach back up and set it.
  static Route<void> route({
    required String folderPath,
    required String folderName,
  }) {
    return MaterialPageRoute(
      settings: RouteSettings(name: folderName),
      builder: (_) => DesktopFolderScreen(
        folderPath: folderPath,
        folderName: folderName,
      ),
    );
  }

  @override
  State<DesktopFolderScreen> createState() => _DesktopFolderScreenState();
}

class _DesktopFolderScreenState extends State<DesktopFolderScreen> {
  /// This folder's own tracks — not its subfolders'. Backs the "Tracks"
  /// section and normal (non-search) playback.
  List<Track> _tracks = [];
  List<Folder> _subfolders = [];

  /// Every track under this folder, subfolders included — the same set
  /// `_playAll` already used. Search spans this, not [_tracks]: most browsable
  /// folders (e.g. a Library-grid entry like "Games") hold *zero* direct
  /// tracks — everything lives one or more album subfolders down — so
  /// filtering [_tracks] alone made search return nothing for almost every
  /// folder in a real library.
  List<Track> _allTracks = [];

  int _totalTrackCount = 0;
  String _query = '';

  // Drives "follow the playing track": scroll the list to the current song.
  final ItemScrollController _itemScrollController = ItemScrollController();
  // Last track id we scrolled to, so we only follow on an actual change.
  String? _followedTrackId;

  AudioPlayerService? _playerForListener;
  LibraryScanner? _scannerForListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playerForListener = context.read<AudioPlayerService>()
        ..addListener(_followCurrentTrack);
      // A background refresh (LibraryScanner.scan()'s phase 2, or an explicit
      // rescan) that lands while this screen is open would otherwise be
      // invisible here.
      _scannerForListener = context.read<LibraryScanner>()
        ..addListener(_loadContents);
      _loadContents();
    });
  }

  @override
  void dispose() {
    _playerForListener?.removeListener(_followCurrentTrack);
    _scannerForListener?.removeListener(_loadContents);
    super.dispose();
  }

  void _loadContents() {
    if (!mounted) return;
    final scanner = context.read<LibraryScanner>();
    final contents = scanner.getFolderContents(widget.folderPath);
    setState(() {
      _subfolders = contents.folders;
      _tracks = contents.tracks;
      _allTracks = scanner.getAllTracksInFolder(widget.folderPath);
      _totalTrackCount = _allTracks.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _followCurrentTrack());
  }

  List<Track> get _visibleTracks {
    if (_query.isEmpty) return _tracks;
    final needle = _query.toLowerCase();
    // Recursive, not [_tracks]: see [_allTracks]'s doc.
    return _allTracks.where((t) => t.title.toLowerCase().contains(needle)).toList();
  }

  bool get _showSubfolders => _query.isEmpty && _subfolders.isNotEmpty;

  /// Number of non-track rows preceding the track rows, so a track's index in
  /// [_visibleTracks] can be mapped to its row position for scroll-to. The
  /// rows are: [Albums label][subfolders][divider][Tracks label][tracks].
  int get _leadingRowCount {
    final hasTracks = _visibleTracks.isNotEmpty;
    var count = 0;
    if (_showSubfolders) {
      count += 1 + _subfolders.length; // label + rows
      if (hasTracks) count += 1; // divider
    }
    if (hasTracks) count += 1; // "Tracks" label
    return count;
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
    final index = _visibleTracks.indexWhere((t) => t.id == id);
    if (index < 0) return; // not in this list — leave _followedTrackId unset
    if (!_itemScrollController.isAttached) return; // retried on next change
    _followedTrackId = id;
    _itemScrollController.scrollTo(
      index: _leadingRowCount + index,
      alignment: 0.3,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  /// Play everything under this folder, subfolders included — the same
  /// recursive set both buttons act on, sequential or shuffled.
  void _playAll({required bool shuffled}) {
    if (_allTracks.isEmpty) return;
    final player = context.read<AudioPlayerService>();
    if (shuffled) {
      player.playShuffled(_allTracks);
    } else {
      player.play(_allTracks);
    }
  }

  void _openSubfolder(Folder folder) {
    Navigator.of(context).push(DesktopFolderScreen.route(
      folderPath: folder.folderPath,
      folderName: folder.displayName,
    ));
  }

  /// Open an ancestor by full path. Always pushes rather than popping back,
  /// because the user may have reached the current folder by a route that
  /// doesn't contain the target (search, or a jump from the player). The back
  /// button still unwinds real history.
  ///
  /// Exception: the auto-flattened root (the lone top-level folder whose
  /// children are surfaced directly on the library screen) goes home instead,
  /// since a folder screen for it would just duplicate the library.
  void _openPath(String fullPath, String displayName) {
    if (context.read<LibraryScanner>().isFlattenedRoot(fullPath)) {
      _goHome();
      return;
    }
    Navigator.of(context).push(DesktopFolderScreen.route(
      folderPath: fullPath,
      folderName: displayName,
    ));
  }

  void _goHome() => Navigator.of(context).popUntil((route) => route.isFirst);

  void _playTrack(Track track) {
    final player = context.read<AudioPlayerService>();
    // Already the current track — don't restart it; the mini player is right
    // there and still playing it.
    if (player.currentTrack?.id == track.id) return;
    if (_query.isEmpty) {
      // This folder's own "Tracks" section — continue through the rest of it.
      player.play(_tracks, from: _tracks.indexOf(track));
    } else {
      // A search match may live in a subfolder album, not in [_tracks] at
      // all — play from the recursive set search actually searched, so
      // playback continues into the rest of what the search was looking
      // through, not just the direct-children list the match may be absent
      // from.
      player.play(_allTracks, from: _allTracks.indexOf(track));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTracks;

    return ColoredBox(
      color: AppColors.win,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Breadcrumb(
              folderPath: widget.folderPath,
              onHome: _goHome,
              onOpenPath: _openPath,
            ),
            const SizedBox(height: 16),
            _Header(
              title: widget.folderName,
              subtitle: _query.isEmpty
                  ? '$_totalTrackCount track(s)'
                  : '${visible.length} result(s)',
              onQueryChanged: (q) => setState(() => _query = q),
              onPlayAll:
                  _totalTrackCount > 0 ? () => _playAll(shuffled: false) : null,
              onShuffle:
                  _totalTrackCount > 0 ? () => _playAll(shuffled: true) : null,
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildContent(visible)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<Track> visible) {
    if (_tracks.isEmpty && _subfolders.isEmpty) {
      return const Center(
        child:
            Text('No content found', style: TextStyle(color: AppColors.muted)),
      );
    }
    if (_query.isNotEmpty && visible.isEmpty) {
      return const Center(
        child: Text('No tracks match your search',
            style: TextStyle(color: AppColors.muted)),
      );
    }

    // One flat list, not nested scrollers: ScrollablePositionedList addresses
    // rows by index for "follow the playing track", so the section headers
    // and album rows have to be rows in the same list — see [_leadingRowCount].
    final leading = _leadingRowCount;

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemCount: leading + visible.length,
      itemBuilder: (context, i) {
        if (i >= leading) {
          final index = i - leading;
          final track = visible[index];
          return DesktopTrackRow(
            track: track,
            // `index` is already the right position: outside search this
            // list *is* `_tracks`, and while searching there's no single
            // "real" position to show — a match can come from any subfolder
            // — so, like the Library and All Tracks search results, this
            // numbers by position among the results themselves.
            number: index + 1,
            onTap: () => _playTrack(track),
          );
        }

        if (_showSubfolders) {
          if (i == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: SectionLabel('Albums'),
            );
          }
          if (i <= _subfolders.length) {
            final folder = _subfolders[i - 1];
            return _AlbumRow(
              folder: folder,
              onTap: () => _openSubfolder(folder),
            );
          }
          if (i == _subfolders.length + 1 && visible.isNotEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: AppColors.border),
            );
          }
        }
        // The only leading row left is the "Tracks" label.
        return const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: SectionLabel('Tracks'),
        );
      },
    );
  }
}

/// `Library / Animes & Animations / Bleach` — ancestors are links, the
/// current folder is plain bold text.
class _Breadcrumb extends StatelessWidget {
  final String folderPath;
  final VoidCallback onHome;
  final void Function(String path, String name) onOpenPath;

  const _Breadcrumb({
    required this.folderPath,
    required this.onHome,
    required this.onOpenPath,
  });

  @override
  Widget build(BuildContext context) {
    final scanner = context.read<LibraryScanner>();
    final segments = folderPath.split('/').where((s) => s.isNotEmpty).toList();

    final children = <Widget>[
      const Icon(Icons.folder_outlined, size: 13, color: AppColors.muted),
      const SizedBox(width: 6),
      _Crumb(label: 'Library', color: AppColors.muted, onTap: onHome),
    ];

    var accumulated = '';
    for (var i = 0; i < segments.length; i++) {
      accumulated =
          accumulated.isEmpty ? segments[i] : '$accumulated/${segments[i]}';
      // The auto-flattened root is already what "Library" points at —
      // rendering it again would be two crumbs for one destination.
      if (scanner.isFlattenedRoot(accumulated)) continue;

      final isLast = i == segments.length - 1;
      final path = accumulated;
      final name = segments[i];

      children
        ..add(const _Separator())
        ..add(isLast
            ? _Crumb(label: name, color: AppColors.text, bold: true)
            : _Crumb(
                label: name,
                color: AppColors.accentText,
                onTap: () => onOpenPath(path, name),
              ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    );
  }
}

class _Crumb extends StatelessWidget {
  final String label;
  final Color color;
  final bool bold;
  final VoidCallback? onTap;

  const _Crumb({
    required this.label,
    required this.color,
    this.bold = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        color: color,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    );

    if (onTap == null) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: text),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child:
            Text('/', style: TextStyle(fontSize: 12.5, color: AppColors.faint)),
      );
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffle;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onQueryChanged,
    required this.onPlayAll,
    required this.onShuffle,
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
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        DesktopSearchField(
          onChanged: onQueryChanged,
          hintText: 'Search tracks...',
          width: 200,
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: onPlayAll,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Play All'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onShuffle,
          icon: const Icon(Icons.shuffle, size: 16),
          label: const Text('Shuffle'),
        ),
      ],
    );
  }
}

/// One subfolder row: 44px art, name, track count, chevron.
class _AlbumRow extends StatelessWidget {
  final Folder folder;
  final VoidCallback onTap;

  const _AlbumRow({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          CoverArt(
            folder,
            size: 44,
            radius: 6,
            fallbackIcon: Icons.folder_outlined,
            fallbackIconColor: AppColors.faint,
            fallbackIconSize: 22,
            showPlaceholder: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              folder.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (folder.subtitle.isNotEmpty)
            Text(
              folder.subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.faint),
        ],
      ),
    );
  }
}
