import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';

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

    final bufferedPosition = playerService.bufferedPosition ?? Duration.zero;
    final bufferedProgress = duration.inMilliseconds > 0
        ? bufferedPosition.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Album Art
                  Container(
                    width: 300,
                    height: 300,
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
                                child: const Icon(
                                  Icons.music_note,
                                  size: 120,
                                  color: Colors.white54,
                                ),
                              ),
                            )
                          : Container(
                              color: Colors.grey[800],
                              child: const Icon(
                                Icons.music_note,
                                size: 120,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 40),

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
                  const SizedBox(height: 40),

                  // Progress Bar
                  Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8,
                              ),
                              // Show buffered content as lighter track
                              inactiveTrackColor: Colors.grey[300],
                            ),
                            child: Stack(
                              children: [
                                // Buffered progress indicator (underneath)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: bufferedProgress.clamp(0.0, 1.0),
                                      backgroundColor: Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.grey[400]!,
                                      ),
                                      minHeight: 4,
                                    ),
                                  ),
                                ),
                                // Main slider (on top)
                                Slider(
                                  value: progress.clamp(0.0, 1.0),
                                  onChanged: (value) {
                                    final newPosition = Duration(
                                      milliseconds:
                                          (value * duration.inMilliseconds).round(),
                                    );
                                    playerService.seek(newPosition);
                                  },
                                ),
                              ],
                            ),
                          ),
                          // Show seeking indicator when buffering after a long seek
                          if (playerService.isSeeking)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Seeking...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
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
                  ),
                  const SizedBox(height: 40),

                  // Playback Controls
                  Row(
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
                            playerService.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
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
                  ),
                  const SizedBox(height: 20),

                  // Shuffle and Repeat Buttons
                  if (playerService.playlist.length > 1)
                    Row(
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
                    ),
                  const SizedBox(height: 32),

                  // Volume Control
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
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
                    ),
                  ),
                  const SizedBox(height: 20),

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
          ),
        ),
      ),
    );
  }
}
