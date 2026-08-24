import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/library_scanner.dart';
import '../utils/responsive.dart';
import '../widgets/track_tile.dart';
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

  // Drives "follow the playing track": scroll the list to the current song.
  final ItemScrollController _itemScrollController = ItemScrollController();
  // Last track id we scrolled to, so we only follow on an actual change.
  String? _followedTrackId;

  @override
  void initState() {
    super.initState();
    _loadInitialTracks();
    context.read<AudioPlayerService>().addListener(_followCurrentTrack);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    try {
      context.read<LibraryScanner>().removeListener(_onScannerUpdate);
      context.read<AudioPlayerService>().removeListener(_followCurrentTrack);
    } catch (_) {}
    super.dispose();
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
    final index = _tracks.indexWhere((t) => t.id == id);
    if (index < 0) return; // not in this list — leave _followedTrackId unset
    if (!_itemScrollController.isAttached) return; // retried on next change/open
    _followedTrackId = id;
    _itemScrollController.scrollTo(
      index: index,
      alignment: 0.3,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  /// Load all songs from the library scanner's cached data.
  void _loadInitialTracks() {
    if (!mounted) return;
    final scanner = context.read<LibraryScanner>();

    if (!scanner.hasInitialData) {
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _followCurrentTrack());
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
    // If this track is already the current one, don't restart it — just open
    // the player and let it keep playing from where it is.
    if (playerService.currentTrack?.id != track.id) {
      // Always play from the full library so playback continues past tracks
      // that didn't match the current search.
      playerService.play(_allTracks, from: _allTracks.indexOf(track));
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _playAll() {
    if (_tracks.isEmpty) return;

    final playerService = context.read<AudioPlayerService>();
    playerService.playShuffled(_tracks);

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

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        return TrackTile(
          track: track,
          leadingIndex: index,
          onTap: () => _playTrack(track),
        );
      },
    );
  }
}

// Track rows are TrackTile (lib/widgets/track_tile.dart).
