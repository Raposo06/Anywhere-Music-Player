// `RepeatMode` collides with Flutter's own (unrelated) animation-builder
// class of the same name — hide theirs so ours from audio_player_service.dart
// resolves unambiguously.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/auth_service.dart';
import '../services/library_scanner.dart';
import '../services/stream_url_resolver.dart';
import '../utils/now_playing_folder.dart';
import '../utils/responsive.dart';
import '../widgets/favourite_button.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/scrub_bar.dart';
import '../widgets/upcoming_cover_precacher.dart';
import 'folder_detail_screen.dart';

/// The artist to display on the player, or null when there's nothing
/// meaningful — an empty tag or Navidrome's '[Unknown Artist]' placeholder is
/// treated as "no artist" so the line is hidden entirely.
String? _displayArtist(Track track) {
  final artist = track.artist?.trim();
  if (artist == null ||
      artist.isEmpty ||
      artist.toLowerCase() == '[unknown artist]') {
    return null;
  }
  return artist;
}

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

  final _coverPrecacher = UpcomingCoverPrecacher();

  // Last playback error shown in a SnackBar, so the same error isn't
  // re-shown on every rebuild while it's still the current error.
  String? _shownError;

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

        // Resolve to the scan's copy so the folder line (and its tap-through)
        // uses the real filesystem path even when playback started from a
        // playlist, whose tracks carry tag-based paths.
        track = canonicalTrack(track, context.read<LibraryScanner>());

        final duration = track.durationSeconds != null
            ? Duration(seconds: track.durationSeconds!)
            : Duration.zero;

        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final isWideScreen = screenWidth > 900;

        final albumArtSize = isWideScreen
            ? (screenHeight * 0.5).clamp(250.0, 400.0)
            : (screenWidth * 0.6).clamp(200.0, 350.0);

        // Defer to the next frame so we don't call precacheImage during a
        // build phase. The precacher itself is a no-op until the track changes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _coverPrecacher.precache(context, logicalSize: albumArtSize.toDouble());
          }
        });

        final horizontalPadding = Responsive.getHorizontalPadding(context);

        final error = context.select<AudioPlayerService, String?>(
          (ps) => ps.lastError,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (error != null && error != _shownError) {
            _shownError = error;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error), duration: const Duration(seconds: 6)),
            );
          } else if (error == null) {
            _shownError = null;
          }
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Now Playing'),
            actions: [
              FavouriteButton(track: track, size: 22),
              IconButton(
                icon: const Icon(Icons.queue_music),
                tooltip: 'Queue',
                onPressed: () => QueueSheet.show(context),
              ),
            ],
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
              // Artist — shown only when meaningful (skips empty tags and the
              // '[Unknown Artist]' placeholder). Album is omitted: it's almost
              // always the same as the folder shown just below.
              if (_displayArtist(track) case final artist?) ...[
                const SizedBox(height: 8),
                Text(
                  artist,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              if (nowPlayingFolderPath(track) case final folderLine
                  when folderLine.isNotEmpty) ...[
                const SizedBox(height: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _openFolder(track),
                    child: Text(
                      folderLine,
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
        // Artist — shown only when meaningful (skips empty tags and the
        // '[Unknown Artist]' placeholder). Album is omitted: it's almost
        // always the same as the folder shown just below.
        if (_displayArtist(track) case final artist?) ...[
          const SizedBox(height: 8),
          Text(
            artist,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (nowPlayingFolderPath(track) case final folderLine
            when folderLine.isNotEmpty) ...[
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _openFolder(track),
              child: Text(
                folderLine,
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
    // Server-side resize: ask Navidrome for an image at the actual pixel
    // size we render. Without this the screen downloads the full-res master
    // (often 1500–2000px / 1–2 MB) just to display a 350-px square, which
    // both wastes bandwidth and balloons the in-memory image cache.
    final pixelSize =
        (size * MediaQuery.devicePixelRatioOf(context)).round();
    final StreamUrlResolver? resolver = context.watch<AuthService>().apiService;
    final sizedUrl = resolver.resolveCoverUrl(track, size: pixelSize);
    final sizedCacheKey = track.coverCacheKey(size: pixelSize);

    final art = Container(
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
        child: sizedUrl != null
            ? CachedNetworkImage(
                imageUrl: sizedUrl,
                cacheKey: sizedCacheKey,
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.music_note,
                    size: size * 0.4,
                    color: Colors.white54,
                  ),
                ),
              )
            : Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.music_note,
                  size: size * 0.4,
                  color: Colors.white54,
                ),
              ),
      ),
    );

    // Only wire up tap navigation when there's a folder line to match
    // (root-level tracks, and tracks whose only path segment is the top-level
    // category, shouldn't pretend to be clickable).
    if (nowPlayingFolderPath(track).isEmpty) return art;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openFolder(track),
        child: art,
      ),
    );
  }
}

/// The phone player's position bar: a full-width slider with plain elapsed /
/// total labels beneath. The drag/seek machinery lives in [ScrubBar].
class _ProgressBar extends StatelessWidget {
  final Duration duration;

  const _ProgressBar({required this.duration});

  @override
  Widget build(BuildContext context) {
    final ps = context.read<AudioPlayerService>();
    return ScrubBar(
      duration: duration,
      trackId: ps.currentTrack?.id,
      position: ps.positionStream,
      onSeek: ps.seek,
      builder: (context, view) => Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: view.fraction,
              onChanged: view.onChanged,
              onChangeStart: view.onChangeStart,
              onChangeEnd: view.onChangeEnd,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatPlaybackDuration(view.position)),
                Text(formatPlaybackDuration(duration)),
              ],
            ),
          ),
        ],
      ),
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
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        );
      },
    );
  }
}
