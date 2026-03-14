import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/audio_player_service.dart';
import '../services/subsonic_api_service.dart';
import '../models/folder.dart';
import '../models/track.dart';
import '../widgets/tv_player_controls.dart';

/// Android TV optimized home screen with leanback design
/// Features:
/// - Large text and touch targets for 10-foot UI
/// - D-pad navigation support
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
  bool _isLoadingFolders = false;
  bool _isLoadingTracks = false;
  String? _selectedFolderId;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  SubsonicApiService? get _api => context.read<AuthService>().apiService;

  Future<void> _loadFolders() async {
    final api = _api;
    if (api == null) return;

    setState(() => _isLoadingFolders = true);

    try {
      final folders = await api.getFolders();

      setState(() {
        _folders = folders;
        _isLoadingFolders = false;
      });
    } catch (e) {
      debugPrint('Error loading folders: $e');
      setState(() => _isLoadingFolders = false);
    }
  }

  Future<void> _loadTracks(Folder folder) async {
    final api = _api;
    if (api == null || folder.id == null) return;

    setState(() {
      _isLoadingTracks = true;
      _selectedFolderId = folder.id;
    });

    try {
      final contents = await api.getDirectoryContents(folder.id!);

      setState(() {
        _tracks = contents.tracks;
        _isLoadingTracks = false;
      });
    } catch (e) {
      debugPrint('Error loading tracks: $e');
      setState(() => _isLoadingTracks = false);
    }
  }

  void _playTrack(Track track, int index) {
    final audioPlayer = context.read<AudioPlayerService>();
    audioPlayer.playPlaylist(_tracks, index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F), // TV dark background
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Row(
              children: [
                // Left sidebar - Folders list
                SizedBox(
                  width: 400,
                  child: _buildFoldersList(),
                ),

                // Right content - Tracks grid
                Expanded(
                  child: _buildTracksGrid(),
                ),
              ],
            ),
          ),

          // Player controls overlay at bottom
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: TvPlayerControls(),
          ),
        ],
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
            child: _isLoadingFolders
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  )
                : ListView.builder(
                    itemCount: _folders.length,
                    itemBuilder: (context, index) {
                      final folder = _folders[index];
                      final isSelected = folder.id == _selectedFolderId;

                      return _TvFolderCard(
                        folder: folder,
                        isSelected: isSelected,
                        onTap: () => _loadTracks(folder),
                        autofocus: index == 0,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTracksGrid() {
    if (_selectedFolderId == null) {
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

    if (_isLoadingTracks) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
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
  final bool autofocus;

  const _TvFolderCard({
    required this.folder,
    required this.isSelected,
    required this.onTap,
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
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
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
                ? const Color(0xFF2D5F9F) // Selected blue
                : _isFocused
                    ? const Color(0xFF2A2A2A) // Focused gray
                    : const Color(0xFF1F1F1F), // Normal dark
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
                    color: widget.isSelected ? Colors.white : Colors.grey[300],
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

  const _TvTrackCard({
    required this.track,
    required this.onTap,
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
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
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
                      widget.track.artist ?? 'Unknown Artist',
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
