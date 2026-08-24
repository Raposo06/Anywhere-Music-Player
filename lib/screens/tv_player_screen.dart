// `RepeatMode` collides with Flutter's own (unrelated) animation-builder
// class of the same name — hide theirs so ours from audio_player_service.dart
// resolves unambiguously.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/auth_service.dart';
import '../services/stream_url_resolver.dart';

/// Full-screen TV player with large cover art and D-pad navigable controls.
class TvPlayerScreen extends StatefulWidget {
  const TvPlayerScreen({super.key});

  @override
  State<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends State<TvPlayerScreen> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: SafeArea(
          child: Selector<AudioPlayerService, Track?>(
            selector: (_, ps) => ps.currentTrack,
            builder: (context, track, _) {
              if (track == null) {
                return const Center(
                  child: Text(
                    'No track playing',
                    style: TextStyle(color: Colors.white54, fontSize: 24),
                  ),
                );
              }

              final screenHeight = MediaQuery.of(context).size.height;
              // Give the cover more breathing room so it's the focal point
              // of the screen — controls below were dialed down to compensate.
              final artSize = (screenHeight * 0.42).clamp(180.0, 420.0);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 16),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Album art
                    _buildAlbumArt(context, track, artSize),
                    const Spacer(flex: 1),

                    // Track title
                    Text(
                      track.title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Subtitle (folder path / artist)
                    Text(
                      track.folderPath.isNotEmpty
                          ? track.folderPath
                          : 'Unknown Artist',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[400],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(flex: 1),

                    // Progress bar
                    _TvProgressBar(
                      duration: track.durationSeconds != null
                          ? Duration(seconds: track.durationSeconds!)
                          : Duration.zero,
                    ),
                    const SizedBox(height: 16),

                    // Playback controls
                    const _TvPlaybackControls(),
                    const SizedBox(height: 12),

                    // Shuffle / Repeat
                    const _TvShuffleRepeatRow(),
                    const SizedBox(height: 8),

                    // Playlist info
                    const _TvPlaylistInfo(),

                    const Spacer(flex: 1),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context, Track track, double size) {
    // Server-side resize: request exactly the pixel size we'll render so we
    // don't pull the full-res master (and explode the image cache) for a
    // 420-px square.
    final pixelSize =
        (size * MediaQuery.devicePixelRatioOf(context)).round();
    final StreamUrlResolver? resolver = context.watch<AuthService>().apiService;
    final sizedUrl = resolver.resolveCoverUrl(track, size: pixelSize);
    final sizedCacheKey = track.coverCacheKey(size: pixelSize);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 30,
            offset: Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: sizedUrl != null
            ? CachedNetworkImage(
                imageUrl: sizedUrl,
                cacheKey: sizedCacheKey,
                // contain (not cover) so non-square art shows in full
                // instead of getting cropped to the square frame.
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => _placeholderArt(size),
              )
            : _placeholderArt(size),
      ),
    );
  }

  Widget _placeholderArt(double size) {
    return Container(
      color: Colors.grey[800],
      child: Icon(
        Icons.music_note,
        size: size * 0.35,
        color: Colors.white54,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress bar
// ---------------------------------------------------------------------------

class _TvProgressBar extends StatelessWidget {
  final Duration duration;
  const _TvProgressBar({required this.duration});

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayerService>();

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final progress = duration.inMilliseconds > 0
            ? (pos.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.grey[700],
                thumbColor: Colors.white,
              ),
              child: Slider(value: progress, onChanged: null),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos),
                      style: TextStyle(fontSize: 16, color: Colors.grey[400])),
                  Text(_fmt(duration),
                      style: TextStyle(fontSize: 16, color: Colors.grey[400])),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Playback controls (prev / play-pause / next)
// ---------------------------------------------------------------------------

class _TvPlaybackControls extends StatelessWidget {
  const _TvPlaybackControls();

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayerService>();

    return StreamBuilder<bool>(
      stream: player.playingStream,
      builder: (context, playSnap) {
        final isPlaying = playSnap.data ?? false;

        return Selector<AudioPlayerService, int>(
          selector: (_, ps) => ps.playlist.length,
          builder: (context, playlistLen, _) {
            return FocusTraversalGroup(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _TvControlButton(
                    icon: Icons.skip_previous,
                    onPressed:
                        playlistLen > 1 ? player.playPrevious : () {},
                    size: 52,
                  ),
                  const SizedBox(width: 28),
                  _TvControlButton(
                    icon: isPlaying ? Icons.pause : Icons.play_arrow,
                    onPressed: player.togglePlayPause,
                    size: 64,
                    isPrimary: true,
                    autofocus: true,
                  ),
                  const SizedBox(width: 28),
                  _TvControlButton(
                    icon: Icons.skip_next,
                    onPressed:
                        playlistLen > 1 ? player.playNext : () {},
                    size: 52,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shuffle / Repeat row
// ---------------------------------------------------------------------------

class _TvShuffleRepeatRow extends StatelessWidget {
  const _TvShuffleRepeatRow();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService,
        ({bool shuffle, RepeatMode repeat, int len})>(
      selector: (_, ps) => (
        shuffle: ps.isShuffleEnabled,
        repeat: ps.repeatMode,
        len: ps.playlist.length,
      ),
      builder: (context, s, _) {
        if (s.len <= 1) return const SizedBox.shrink();
        final player = context.read<AudioPlayerService>();

        return FocusTraversalGroup(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TvControlButton(
                icon: Icons.shuffle,
                onPressed: () => player.toggleShuffle(),
                isActive: s.shuffle,
                size: 42,
              ),
              const SizedBox(width: 16),
              Text(
                s.shuffle ? 'Shuffle ON' : 'Shuffle OFF',
                style: TextStyle(
                  color: s.shuffle ? Colors.white : Colors.grey[600],
                  fontSize: 18,
                  fontWeight:
                      s.shuffle ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 48),
              _TvControlButton(
                icon: s.repeat == RepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                onPressed: player.toggleRepeatMode,
                isActive: s.repeat != RepeatMode.off,
                size: 42,
              ),
              const SizedBox(width: 16),
              Text(
                s.repeat == RepeatMode.off
                    ? 'Repeat OFF'
                    : s.repeat == RepeatMode.all
                        ? 'Repeat ALL'
                        : 'Repeat ONE',
                style: TextStyle(
                  color: s.repeat != RepeatMode.off
                      ? Colors.white
                      : Colors.grey[600],
                  fontSize: 18,
                  fontWeight: s.repeat != RepeatMode.off
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Playlist info
// ---------------------------------------------------------------------------

class _TvPlaylistInfo extends StatelessWidget {
  const _TvPlaylistInfo();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, ({int idx, int len})>(
      selector: (_, ps) => (idx: ps.currentIndex, len: ps.playlist.length),
      builder: (context, s, _) {
        if (s.len <= 1) return const SizedBox.shrink();
        return Text(
          'Track ${s.idx + 1} of ${s.len}',
          style: TextStyle(color: Colors.grey[500], fontSize: 18),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable TV control button with D-pad focus support
// ---------------------------------------------------------------------------

class _TvControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final bool isActive;
  final bool isPrimary;
  final bool autofocus;

  const _TvControlButton({
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.isActive = false,
    this.isPrimary = false,
    this.autofocus = false,
  });

  @override
  State<_TvControlButton> createState() => _TvControlButtonState();
}

class _TvControlButtonState extends State<_TvControlButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        // AnimatedContainer + AnimatedScale smooth out the focus change so
        // D-pad navigation feels responsive instead of snapping in/out.
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.isPrimary
                  ? Colors.white
                  : widget.isActive
                      ? const Color(0xFF2D5F9F)
                      : const Color(0xFF2A2A2A),
              shape: BoxShape.circle,
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.5,
              color: widget.isPrimary ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
