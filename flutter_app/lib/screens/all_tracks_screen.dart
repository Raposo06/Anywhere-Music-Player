import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../services/auth_service.dart';
import '../services/subsonic_api_service.dart';
import '../services/audio_player_service.dart';
import '../utils/responsive.dart';
import 'player_screen.dart';

class AllTracksScreen extends StatefulWidget {
  const AllTracksScreen({super.key});

  @override
  State<AllTracksScreen> createState() => _AllTracksScreenState();
}

class _AllTracksScreenState extends State<AllTracksScreen> {
  final _searchController = TextEditingController();
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
    super.dispose();
  }

  SubsonicApiService? get _api => context.read<AuthService>().apiService;

  /// Load songs immediately on screen open using getRandomSongs.
  Future<void> _loadInitialTracks() async {
    if (!mounted) return;
    final api = _api;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tracks = await api.getRandomSongs(size: 200);

      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load tracks: $e';
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      // Return to initial random tracks
      _loadInitialTracks();
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
      final result = await api.search3(query, songCount: 100);

      if (!mounted) return;
      if (_searchQuery != query) return;

      setState(() {
        _tracks = result.songs;
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

  void _playTrack(Track track) {
    final playerService = context.read<AudioPlayerService>();
    final trackIndex = _tracks.indexOf(track);
    playerService.playPlaylist(_tracks, trackIndex);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _playAll() {
    if (_tracks.isEmpty) return;

    final playerService = context.read<AudioPlayerService>();
    playerService.playPlaylist(_tracks, 0);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
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
                          ? 'Discover (${_tracks.length} tracks)'
                          : 'Results (${_tracks.length} tracks)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_tracks.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchQuery.isEmpty)
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _loadInitialTracks,
                              tooltip: 'Shuffle new tracks',
                            ),
                          ElevatedButton.icon(
                            onPressed: _playAll,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play All'),
                          ),
                        ],
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
              onPressed: _searchQuery.isEmpty ? _loadInitialTracks : () => _performSearch(_searchQuery),
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

        return ListTile(
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
            '${track.artist ?? ''} ${track.formattedDuration}'.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isCurrentTrack
              ? const Icon(Icons.equalizer, color: Colors.blue)
              : null,
          onTap: onTap,
        );
      },
    );
  }
}
