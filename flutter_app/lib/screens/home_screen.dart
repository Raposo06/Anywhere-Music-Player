import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/audio_player_service.dart';
import 'player_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  List<Track> _tracks = [];
  Map<String, List<Track>> _groupedTracks = {};
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final tracks = await apiService.getTracks();

      setState(() {
        _tracks = tracks;
        _groupedTracks = _groupTracksByFolder(tracks);
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load tracks';
        _isLoading = false;
      });
    }
  }

  Map<String, List<Track>> _groupTracksByFolder(List<Track> tracks) {
    final grouped = <String, List<Track>>{};
    for (var track in tracks) {
      grouped[track.folderPath] ??= [];
      grouped[track.folderPath]!.add(track);
    }
    return grouped;
  }

  Future<void> _handleSearch(String query) async {
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

      setState(() {
        _tracks = tracks;
        _groupedTracks = _groupTracksByFolder(tracks);
        _isLoading = false;
      });
    } on ApiException catch (e) {
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

  void _playTrack(Track track, List<Track> folderTracks) {
    final playerService = context.read<AudioPlayerService>();
    final trackIndex = folderTracks.indexOf(track);
    playerService.playPlaylist(folderTracks, trackIndex);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final playerService = context.watch<AudioPlayerService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Library'),
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
                hintText: 'Search tracks or folders...',
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

          // User info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Welcome, ${authService.currentUser?.username ?? "User"}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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

    // Sort folders alphabetically
    final sortedFolders = _groupedTracks.keys.toList()..sort();

    return ListView.builder(
      itemCount: sortedFolders.length,
      itemBuilder: (context, index) {
        final folder = sortedFolders[index];
        final tracks = _groupedTracks[folder]!;

        return ExpansionTile(
          leading: const Icon(Icons.folder, color: Colors.blue),
          title: Text(
            folder,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Text('${tracks.length} track(s)'),
          initiallyExpanded: sortedFolders.length == 1,
          children: tracks.map((track) {
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
              subtitle: Text(track.formattedDuration),
              trailing: isCurrentTrack
                  ? const Icon(Icons.equalizer, color: Colors.blue)
                  : null,
              onTap: () => _playTrack(track, tracks),
            );
          }).toList(),
        );
      },
    );
  }
}
