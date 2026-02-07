import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';
import '../utils/responsive.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Focus nodes for D-Pad navigation
  final _playPauseFocusNode = FocusNode();
  final _previousFocusNode = FocusNode();
  final _nextFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus play/pause button for TV remote
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playPauseFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _playPauseFocusNode.dispose();
    _previousFocusNode.dispose();
    _nextFocusNode.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      // HH:MM:SS for 1 hour+ tracks
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      // MM:SS for shorter tracks
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<AudioPlayerService>();
    final track = playerService.currentTrack;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Player')),
        body: const Center(
          child: Text('No track playing'),
        ),
      );
    }

    final position = playerService.position ?? Duration.zero;
    // Always use database duration since it's accurate
    final duration = track.durationSeconds != null
        ? Duration(seconds: track.durationSeconds!)
        : Duration.zero;

    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    // Responsive layout calculations
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWideScreen = screenWidth > 900;
    final isDesktop = Responsive.isDesktopOrLarger(context);

    // Dynamic album art size based on screen
    final albumArtSize = isWideScreen
        ? (screenHeight * 0.5).clamp(250.0, 400.0)
        : (screenWidth * 0.6).clamp(200.0, 350.0);

    final horizontalPadding = Responsive.getHorizontalPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWideScreen ? 1200 : 600,
            ),
            child: Padding(
              padding: EdgeInsets.all(horizontalPadding),
              child: isWideScreen
                  ? _buildWideLayout(
                      track: track,
                      playerService: playerService,
                      albumArtSize: albumArtSize,
                      position: position,
                      duration: duration,
                      progress: progress,
                    )
                  : _buildNarrowLayout(
                      track: track,
                      playerService: playerService,
                      albumArtSize: albumArtSize,
                      position: position,
                      duration: duration,
                      progress: progress,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Wide layout for desktop - album art on left, controls on right
  Widget _buildWideLayout({
    required track,
    required AudioPlayerService playerService,
    required double albumArtSize,
    required Duration position,
    required Duration duration,
    required double progress,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Album Art (left side)
        _buildAlbumArt(track, albumArtSize),
        const SizedBox(width: 48),
        // Controls (right side)
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Track Info
              Text(
                track.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                track.folderPath,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 32),
              // Progress Bar
              _buildProgressBar(playerService, position, duration, progress),
              const SizedBox(height: 32),
              // Playback Controls
              _buildPlaybackControls(playerService),
              const SizedBox(height: 24),
              // Shuffle and Repeat
              if (playerService.playlist.length > 1)
                _buildShuffleRepeatControls(playerService),
              const SizedBox(height: 24),
              // Volume Control
              _buildVolumeControl(playerService),
              const SizedBox(height: 16),
              // Playlist Info
              if (playerService.playlist.length > 1)
                Text(
                  'Track ${playerService.currentIndex + 1} of ${playerService.playlist.length}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Narrow layout for mobile - stacked vertically
  Widget _buildNarrowLayout({
    required track,
    required AudioPlayerService playerService,
    required double albumArtSize,
    required Duration position,
    required Duration duration,
    required double progress,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Album Art
        _buildAlbumArt(track, albumArtSize),
        const SizedBox(height: 32),
        // Track Info
        Text(
          track.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          track.folderPath,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // Progress Bar
        _buildProgressBar(playerService, position, duration, progress),
        const SizedBox(height: 32),
        // Playback Controls
        _buildPlaybackControls(playerService),
        const SizedBox(height: 20),
        // Shuffle and Repeat
        if (playerService.playlist.length > 1)
          _buildShuffleRepeatControls(playerService),
        const SizedBox(height: 24),
        // Volume Control
        _buildVolumeControl(playerService),
        const SizedBox(height: 16),
        // Playlist Info
        if (playerService.playlist.length > 1)
          Text(
            'Track ${playerService.currentIndex + 1} of ${playerService.playlist.length}',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
      ],
    );
  }

  Widget _buildAlbumArt(track, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: track.coverArtUrl != null
            ? Image.network(
                track.coverArtUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[800],
                  child: Icon(
                    Icons.music_note,
                    size: size * 0.4,
                    color: Colors.white54,
                  ),
                ),
              )
            : Container(
                color: Colors.grey[800],
                child: Icon(
                  Icons.music_note,
                  size: size * 0.4,
                  color: Colors.white54,
                ),
              ),
      ),
    );
  }

  Widget _buildProgressBar(
    AudioPlayerService playerService,
    Duration position,
    Duration duration,
    double progress,
  ) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
            ),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (value) {
              final newPosition = Duration(
                milliseconds: (value * duration.inMilliseconds).round(),
              );
              playerService.seek(newPosition);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position)),
              Text(_formatDuration(duration)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(AudioPlayerService playerService) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous Button
        IconButton(
          focusNode: _previousFocusNode,
          icon: const Icon(Icons.skip_previous),
          iconSize: 48,
          onPressed: playerService.currentIndex > 0
              ? playerService.playPrevious
              : null,
        ),
        const SizedBox(width: 20),
        // Play/Pause Button
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).primaryColor,
          ),
          child: IconButton(
            focusNode: _playPauseFocusNode,
            icon: Icon(
              playerService.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            iconSize: 56,
            color: Colors.white,
            onPressed: playerService.togglePlayPause,
          ),
        ),
        const SizedBox(width: 20),
        // Next Button
        IconButton(
          focusNode: _nextFocusNode,
          icon: const Icon(Icons.skip_next),
          iconSize: 48,
          onPressed: playerService.currentIndex <
                  playerService.playlist.length - 1
              ? playerService.playNext
              : null,
        ),
      ],
    );
  }

  Widget _buildShuffleRepeatControls(AudioPlayerService playerService) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle Button
        IconButton(
          icon: Icon(
            Icons.shuffle,
            color: playerService.isShuffleEnabled
                ? Theme.of(context).primaryColor
                : Colors.grey,
          ),
          iconSize: 32,
          onPressed: playerService.toggleShuffle,
          tooltip: playerService.isShuffleEnabled
              ? 'Shuffle: ON'
              : 'Shuffle: OFF',
        ),
        const SizedBox(width: 8),
        Text(
          playerService.isShuffleEnabled ? 'Shuffle ON' : 'Shuffle OFF',
          style: TextStyle(
            color: playerService.isShuffleEnabled
                ? Theme.of(context).primaryColor
                : Colors.grey[600],
            fontSize: 14,
            fontWeight: playerService.isShuffleEnabled
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 32),
        // Repeat Button
        IconButton(
          icon: Icon(
            playerService.repeatMode == RepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            color: playerService.repeatMode != RepeatMode.off
                ? Theme.of(context).primaryColor
                : Colors.grey,
          ),
          iconSize: 32,
          onPressed: playerService.toggleRepeatMode,
          tooltip: playerService.repeatMode == RepeatMode.off
              ? 'Repeat: OFF'
              : playerService.repeatMode == RepeatMode.all
                  ? 'Repeat: ALL'
                  : 'Repeat: ONE',
        ),
        const SizedBox(width: 8),
        Text(
          playerService.repeatMode == RepeatMode.off
              ? 'Repeat OFF'
              : playerService.repeatMode == RepeatMode.all
                  ? 'Repeat ALL'
                  : 'Repeat ONE',
          style: TextStyle(
            color: playerService.repeatMode != RepeatMode.off
                ? Theme.of(context).primaryColor
                : Colors.grey[600],
            fontSize: 14,
            fontWeight: playerService.repeatMode != RepeatMode.off
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeControl(AudioPlayerService playerService) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          playerService.volume == 0
              ? Icons.volume_off
              : playerService.volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
          size: 24,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            value: playerService.volume,
            onChanged: (value) => playerService.setVolume(value),
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: '${(playerService.volume * 100).round()}%',
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '${(playerService.volume * 100).round()}%',
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
