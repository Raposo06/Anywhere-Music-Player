import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../utils/responsive.dart';
import 'folder_detail_screen.dart';

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

  void _openFolder(Track track) {
    if (track.folderPath.isEmpty) return;
    // Use folderName if available, otherwise extract the last path segment
    final displayName = track.folderName.isNotEmpty
        ? track.folderName
        : track.folderPath.contains('/')
            ? track.folderPath.substring(track.folderPath.lastIndexOf('/') + 1)
            : track.folderPath;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(
          folderId: track.folderPath,
          folderName: displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use Selector for track changes (discrete, not high-frequency)
    return Selector<AudioPlayerService, Track?>(
      selector: (_, ps) => ps.currentTrack,
      builder: (context, track, _) {
        if (track == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Player')),
            body: const Center(
              child: Text('No track playing'),
            ),
          );
        }

        final duration = track.durationSeconds != null
            ? Duration(seconds: track.durationSeconds!)
            : Duration.zero;

        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final isWideScreen = screenWidth > 900;

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
                          albumArtSize: albumArtSize,
                          duration: duration,
                        )
                      : _buildNarrowLayout(
                          track: track,
                          albumArtSize: albumArtSize,
                          duration: duration,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWideLayout({
    required Track track,
    required double albumArtSize,
    required Duration duration,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildAlbumArt(track, albumArtSize),
        const SizedBox(width: 48),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (track.folderPath.isNotEmpty) ...[
                const SizedBox(height: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _openFolder(track),
                    child: Text(
                      track.folderPath,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: Theme.of(context).colorScheme.primary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              _ProgressBar(duration: duration),
              const SizedBox(height: 32),
              _PlaybackControls(
                playPauseFocusNode: _playPauseFocusNode,
                previousFocusNode: _previousFocusNode,
                nextFocusNode: _nextFocusNode,
              ),
              const SizedBox(height: 24),
              const _ShuffleRepeatControls(),
              const SizedBox(height: 24),
              const _VolumeControl(),
              const SizedBox(height: 16),
              const _PlaylistInfo(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout({
    required Track track,
    required double albumArtSize,
    required Duration duration,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildAlbumArt(track, albumArtSize),
        const SizedBox(height: 32),
        Text(
          track.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (track.folderPath.isNotEmpty) ...[
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _openFolder(track),
              child: Text(
                track.folderPath,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: Theme.of(context).colorScheme.primary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        const SizedBox(height: 32),
        _ProgressBar(duration: duration),
        const SizedBox(height: 32),
        _PlaybackControls(
          playPauseFocusNode: _playPauseFocusNode,
          previousFocusNode: _previousFocusNode,
          nextFocusNode: _nextFocusNode,
        ),
        const SizedBox(height: 20),
        const _ShuffleRepeatControls(),
        const SizedBox(height: 24),
        const _VolumeControl(),
        const SizedBox(height: 16),
        const _PlaylistInfo(),
      ],
    );
  }

  Widget _buildAlbumArt(Track track, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: track.coverArtUrl != null
            ? CachedNetworkImage(
                imageUrl: track.coverArtUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
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
}

/// Progress bar that uses StreamBuilder for high-frequency position updates
/// instead of rebuilding the entire widget tree via notifyListeners().
/// Uses onChangeStart/onChangeEnd to prevent the position stream from
/// fighting with the user's drag/tap gesture.
class _ProgressBar extends StatefulWidget {
  final Duration duration;

  const _ProgressBar({required this.duration});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  String _formatDuration(Duration? d) {
    if (d == null) return '0:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.read<AudioPlayerService>();

    return StreamBuilder<Duration>(
      stream: playerService.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final streamProgress = widget.duration.inMilliseconds > 0
            ? position.inMilliseconds / widget.duration.inMilliseconds
            : 0.0;

        final displayProgress = streamProgress.clamp(0.0, 1.0);
        final displayPosition = position;

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
                value: displayProgress.clamp(0.0, 1.0),
                onChanged: null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(displayPosition)),
                  Text(_formatDuration(widget.duration)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Playback controls that use Selector/StreamBuilder for efficient rebuilds.
class _PlaybackControls extends StatelessWidget {
  final FocusNode playPauseFocusNode;
  final FocusNode previousFocusNode;
  final FocusNode nextFocusNode;

  const _PlaybackControls({
    required this.playPauseFocusNode,
    required this.previousFocusNode,
    required this.nextFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    final playerService = context.read<AudioPlayerService>();

    return StreamBuilder<bool>(
      stream: playerService.playingStream,
      builder: (context, playingSnapshot) {
        final isPlaying = playingSnapshot.data ?? false;

        return Selector<AudioPlayerService, int>(
          selector: (_, ps) => ps.playlist.length,
          builder: (context, playlistLength, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  focusNode: previousFocusNode,
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 48,
                  onPressed: playlistLength > 1
                      ? playerService.playPrevious
                      : null,
                ),
                const SizedBox(width: 20),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: IconButton(
                    focusNode: playPauseFocusNode,
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    iconSize: 56,
                    color: Colors.white,
                    onPressed: playerService.togglePlayPause,
                  ),
                ),
                const SizedBox(width: 20),
                IconButton(
                  focusNode: nextFocusNode,
                  icon: const Icon(Icons.skip_next),
                  iconSize: 48,
                  onPressed: playlistLength > 1
                      ? playerService.playNext
                      : null,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Shuffle and repeat controls using Selector for targeted rebuilds.
class _ShuffleRepeatControls extends StatelessWidget {
  const _ShuffleRepeatControls();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, ({bool shuffle, RepeatMode repeat, int playlistLength})>(
      selector: (_, ps) => (
        shuffle: ps.isShuffleEnabled,
        repeat: ps.repeatMode,
        playlistLength: ps.playlist.length,
      ),
      builder: (context, state, _) {
        if (state.playlistLength <= 1) return const SizedBox.shrink();

        final playerService = context.read<AudioPlayerService>();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: state.shuffle
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              iconSize: 32,
              onPressed: () => playerService.toggleShuffle(),
              tooltip: state.shuffle ? 'Shuffle: ON' : 'Shuffle: OFF',
            ),
            const SizedBox(width: 8),
            Text(
              state.shuffle ? 'Shuffle ON' : 'Shuffle OFF',
              style: TextStyle(
                color: state.shuffle
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[600],
                fontSize: 14,
                fontWeight: state.shuffle ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 32),
            IconButton(
              icon: Icon(
                state.repeat == RepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                color: state.repeat != RepeatMode.off
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              iconSize: 32,
              onPressed: playerService.toggleRepeatMode,
              tooltip: state.repeat == RepeatMode.off
                  ? 'Repeat: OFF'
                  : state.repeat == RepeatMode.all
                      ? 'Repeat: ALL'
                      : 'Repeat: ONE',
            ),
            const SizedBox(width: 8),
            Text(
              state.repeat == RepeatMode.off
                  ? 'Repeat OFF'
                  : state.repeat == RepeatMode.all
                      ? 'Repeat ALL'
                      : 'Repeat ONE',
              style: TextStyle(
                color: state.repeat != RepeatMode.off
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[600],
                fontSize: 14,
                fontWeight: state.repeat != RepeatMode.off
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Volume control using Selector for targeted rebuilds.
class _VolumeControl extends StatelessWidget {
  const _VolumeControl();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, double>(
      selector: (_, ps) => ps.volume,
      builder: (context, volume, _) {
        final playerService = context.read<AudioPlayerService>();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              volume == 0
                  ? Icons.volume_off
                  : volume < 0.5
                      ? Icons.volume_down
                      : Icons.volume_up,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: volume,
                onChanged: (value) => playerService.setVolume(value),
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: '${(volume * 100).round()}%',
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              child: Text(
                '${(volume * 100).round()}%',
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Playlist info using Selector for targeted rebuilds.
class _PlaylistInfo extends StatelessWidget {
  const _PlaylistInfo();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, ({int index, int length})>(
      selector: (_, ps) => (index: ps.currentIndex, length: ps.playlist.length),
      builder: (context, state, _) {
        if (state.length <= 1) return const SizedBox.shrink();

        return Text(
          'Track ${state.index + 1} of ${state.length}',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        );
      },
    );
  }
}
