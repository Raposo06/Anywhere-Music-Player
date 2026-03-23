import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/audio_player_service.dart';
import '../services/library_scanner.dart';
import '../models/folder.dart';
import '../models/track.dart';
import '../widgets/tv_player_controls.dart';

/// Android TV optimized home screen with leanback design
/// Features:
/// - Large text and touch targets for 10-foot UI
/// - D-pad navigation support with cross-pane focus management
/// - Focus management for remote controls
/// - Dark theme optimized for TV displays
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  List<Folder> _folders = [];
  List<Track> _tracks = [];
  String? _selectedFolderPath;

  // Focus scope nodes for cross-pane D-pad navigation.
  // FocusScopeNode remembers the last focused child, so calling
  // requestFocus() on a scope restores focus to the last item.
  final _sidebarScopeNode = FocusScopeNode(debugLabel: 'sidebar');
  final _gridScopeNode = FocusScopeNode(debugLabel: 'grid');
  final _controlsScopeNode = FocusScopeNode(debugLabel: 'controls');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFolders();
    });
  }

  void _loadFolders() {
    final scanner = context.read<LibraryScanner>();
    if (!scanner.hasScanned) {
      scanner.addListener(_onScannerChanged);
      scanner.scan();
      return;
    }
    setState(() {
      _folders = scanner.getTopLevelFolders();
    });
  }

  void _onScannerChanged() {
    final scanner = context.read<LibraryScanner>();
    if (scanner.hasScanned) {
      scanner.removeListener(_onScannerChanged);
      setState(() {
        _folders = scanner.getTopLevelFolders();
      });
    }
  }

  @override
  void dispose() {
    _sidebarScopeNode.dispose();
    _gridScopeNode.dispose();
    _controlsScopeNode.dispose();
    super.dispose();
  }

  void _loadTracks(Folder folder) {
    final scanner = context.read<LibraryScanner>();
    final contents = scanner.getFolderContents(folder.folderPath);
    setState(() {
      _selectedFolderPath = folder.folderPath;
      _tracks = contents.tracks;
    });
  }

  void _playTrack(Track track, int index) {
    final audioPlayer = context.read<AudioPlayerService>();
    audioPlayer.playPlaylist(_tracks, index);
  }

  /// Handle TV remote back button:
  /// - If a folder is selected → deselect it
  /// - Otherwise → exit the app
  void _handleBackButton() {
    if (_selectedFolderPath != null) {
      setState(() {
        _selectedFolderPath = null;
        _tracks = [];
      });
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackButton();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: Stack(
          children: [
            // Main content
            SafeArea(
              child: Row(
                children: [
                  // Left sidebar - Folders list
                  SizedBox(
                    width: 400,
                    child: FocusScope(
                      node: _sidebarScopeNode,
                      child: FocusTraversalGroup(
                        child: _buildFoldersList(),
                      ),
                    ),
                  ),

                  // Right content - Tracks grid
                  Expanded(
                    child: FocusScope(
                      node: _gridScopeNode,
                      child: FocusTraversalGroup(
                        child: _buildTracksGrid(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Player controls overlay at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FocusScope(
                node: _controlsScopeNode,
                child: FocusTraversalGroup(
                  child: TvPlayerControls(
                    onNavigateUp: () => _gridScopeNode.requestFocus(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoldersList() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Anywhere Music',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Folders',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),

          // Folders list
          Expanded(
            child: _folders.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  )
                : ListView.builder(
                    itemCount: _folders.length,
                    itemBuilder: (context, index) {
                      final folder = _folders[index];
                      final isSelected =
                          folder.folderPath == _selectedFolderPath;

                      return _TvFolderCard(
                        folder: folder,
                        isSelected: isSelected,
                        onTap: () => _loadTracks(folder),
                        autofocus: index == 0,
                        onNavigateRight: () {
                          if (_tracks.isNotEmpty) {
                            _gridScopeNode.requestFocus();
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTracksGrid() {
    if (_selectedFolderPath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note,
              size: 120,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 24),
            Text(
              'Select a folder to view tracks',
              style: TextStyle(
                fontSize: 24,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    if (_tracks.isEmpty) {
      return Center(
        child: Text(
          'No tracks found',
          style: TextStyle(
            fontSize: 24,
            color: Colors.grey[500],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        return _TvTrackCard(
          track: track,
          onTap: () => _playTrack(track, index),
          onNavigateLeft: () => _sidebarScopeNode.requestFocus(),
          onNavigateDown: () => _controlsScopeNode.requestFocus(),
        );
      },
    );
  }
}

/// TV-optimized folder card with focus support
class _TvFolderCard extends StatefulWidget {
  final Folder folder;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onNavigateRight;
  final bool autofocus;

  const _TvFolderCard({
    required this.folder,
    required this.isSelected,
    required this.onTap,
    required this.onNavigateRight,
    this.autofocus = false,
  });

  @override
  State<_TvFolderCard> createState() => _TvFolderCardState();
}

class _TvFolderCardState extends State<_TvFolderCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onNavigateRight();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? const Color(0xFF2D5F9F)
                : _isFocused
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(8),
            border: _isFocused
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder,
                color: widget.isSelected ? Colors.white : Colors.grey[400],
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.folder.displayName,
                  style: TextStyle(
                    fontSize: 20,
                    color:
                        widget.isSelected ? Colors.white : Colors.grey[300],
                    fontWeight: widget.isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TV-optimized track card with focus support
class _TvTrackCard extends StatefulWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateDown;

  const _TvTrackCard({
    required this.track,
    required this.onTap,
    required this.onNavigateLeft,
    required this.onNavigateDown,
  });

  @override
  State<_TvTrackCard> createState() => _TvTrackCardState();
}

class _TvTrackCardState extends State<_TvTrackCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onNavigateLeft();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            // Let the grid handle normal down navigation first;
            // only jump to controls if we can't move down in the grid.
            final didMove = Actions.invoke(
              context,
              DirectionalFocusIntent(TraversalDirection.down),
            );
            if (didMove == null) {
              widget.onNavigateDown();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isFocused
                ? const Color(0xFF2A2A2A)
                : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            border: _isFocused
                ? Border.all(color: Colors.white, width: 3)
                : Border.all(color: const Color(0xFF2A2A2A), width: 1),
          ),
          child: Row(
            children: [
              // Album art or placeholder
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: widget.track.coverArtUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: widget.track.coverArtUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) {
                            return const Icon(
                              Icons.music_note,
                              color: Colors.white54,
                              size: 32,
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.music_note,
                        color: Colors.white54,
                        size: 32,
                      ),
              ),
              const SizedBox(width: 16),

              // Track info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.track.title,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.track.formattedDuration,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Duration
              if (widget.track.durationSeconds != null)
                Text(
                  _formatDuration(widget.track.durationSeconds!),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[500],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }
}
