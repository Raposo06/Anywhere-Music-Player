import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/library_scanner.dart';
import '../utils/responsive.dart';
import 'player_screen.dart';

class AllTracksScreen extends StatefulWidget {
  const AllTracksScreen({super.key});

  @override
  State<AllTracksScreen> createState() => _AllTracksScreenState();
}

class _AllTracksScreenState extends State<AllTracksScreen> {
  final _searchController = TextEditingController();
  // Full sorted library — always the source for playback so the queue keeps
  // playing beyond the search results.
  List<Track> _allTracks = [];
  // What the user currently sees (either _allTracks or a filtered subset).
  List<Track> _tracks = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialTracks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    try {
      context.read<LibraryScanner>().removeListener(_onScannerUpdate);
    } catch (_) {}
    super.dispose();
  }

  /// Load all songs from the library scanner's cached data.
  void _loadInitialTracks() {
    if (!mounted) return;
    final scanner = context.read<LibraryScanner>();

    if (!scanner.hasScanned) {
      // Scanner hasn't finished yet — wait for it
      setState(() => _isLoading = true);
      scanner.addListener(_onScannerUpdate);
      return;
    }

    final tracks = List<Track>.from(scanner.allTracks)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    setState(() {
      _allTracks = tracks;
      _tracks = tracks;
      _isLoading = false;
      _errorMessage = scanner.error;
    });
  }

  void _onScannerUpdate() {
    final scanner = context.read<LibraryScanner>();
    if (!scanner.isScanning) {
      scanner.removeListener(_onScannerUpdate);
      _loadInitialTracks();
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      _loadInitialTracks();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _filterTracks(query);
    });
  }

  void _filterTracks(String query) {
    if (!mounted) return;
    final scanner = context.read<LibraryScanner>();
    final lowerQuery = query.toLowerCase();

    final filtered = scanner.allTracks
        .where((t) => t.title.toLowerCase().contains(lowerQuery))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    setState(() {
      _tracks = filtered;
      _isLoading = false;
    });
  }

  void _playTrack(Track track) {
    final playerService = context.read<AudioPlayerService>();
    // Always play from the full library so playback continues past tracks
    // that didn't match the current search.
    playerService.playPlaylist(_allTracks, _allTracks.indexOf(track));

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _playAll() {
    if (_tracks.isEmpty) return;

    final playerService = context.read<AudioPlayerService>();
    if (!playerService.isShuffleEnabled) {
      playerService.toggleShuffle();
    }
    playerService.playPlaylist(_tracks, -1);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = Responsive.getHorizontalPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Tracks'),
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
                    hintText: 'Search tracks...',
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

              // Header with track count and play all
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _searchQuery.isEmpty
                          ? '${_tracks.length} tracks'
                          : 'Results (${_tracks.length} tracks)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_tracks.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: _playAll,
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Shuffle All'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Track list
              Expanded(
                child: _buildTrackList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackList() {
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
              onPressed: _searchQuery.isEmpty ? _loadInitialTracks : () => _filterTracks(_searchQuery),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No tracks found' : 'No results for "$_searchQuery"',
              style: TextStyle(fontSize: 18, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        return _AllTracksTile(
          track: track,
          index: index,
          onTap: () => _playTrack(track),
        );
      },
    );
  }
}

/// Extracted track tile that uses Selector to avoid rebuilding on position updates.
class _AllTracksTile extends StatelessWidget {
  final Track track;
  final int index;
  final VoidCallback onTap;

  const _AllTracksTile({required this.track, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, String?>(
      selector: (_, ps) => ps.currentTrack?.id,
      builder: (context, currentTrackId, _) {
        final isCurrentTrack = currentTrackId == track.id;

        return Dismissible(
          key: ValueKey('all-$index-${track.id}'),
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
