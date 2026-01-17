import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/audio_player_service.dart';
import 'player_screen.dart';
import 'login_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTracks() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final tracks = await apiService.getTracks();

      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load tracks';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      _loadTracks();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final tracks = await apiService.searchTracks(query);

      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } on ApiException catch (e) {
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

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _playTrack(Track track) {
    final playerService = context.read<AudioPlayerService>();
    final trackIndex = _tracks.indexOf(track);
    playerService.playPlaylist(_tracks, trackIndex);
    // Start playing immediately without navigating to player screen
  }

  void _playAll() {
    if (_tracks.isEmpty) return;

    final playerService = context.read<AudioPlayerService>();
    playerService.playPlaylist(_tracks, 0);
    // Start playing immediately without navigating to player screen
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final playerService = context.watch<AudioPlayerService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Tracks'),
        actions: [
          // Current playing indicator
          if (playerService.currentTrack != null)
            IconButton(
              icon: const Icon(Icons.music_note),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                );
              },
            ),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
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
                          _handleSearch('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: _handleSearch,
            ),
          ),

          // User info and play all button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Welcome, ${authService.currentUser?.username ?? "User"}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_tracks.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _playAll,
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Play All (${_tracks.length})'),
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
      floatingActionButton: playerService.currentTrack != null
          ? FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                );
              },
              child: Icon(
                playerService.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
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
              onPressed: _loadTracks,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tracks.isEmpty) {
      return const Center(
        child: Text('No tracks found'),
      );
    }

    return ListView.builder(
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final isCurrentTrack = context
                .watch<AudioPlayerService>()
                .currentTrack
                ?.id ==
            track.id;

        return ListTile(
          leading: track.coverArtUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    track.coverArtUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
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
          subtitle: Text('${track.folderPath} • ${track.formattedDuration}'),
          trailing: isCurrentTrack
              ? const Icon(Icons.equalizer, color: Colors.blue)
              : null,
          onTap: () => _playTrack(track),
        );
      },
    );
  }
}
