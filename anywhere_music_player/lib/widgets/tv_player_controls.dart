import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';

/// TV-optimized player controls with D-pad navigation
/// Displays at bottom of screen with large buttons for remote control
class TvPlayerControls extends StatelessWidget {
  const TvPlayerControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerService>(
      builder: (context, audioPlayer, child) {
        final track = audioPlayer.currentTrack;

        if (track == null) {
          return const SizedBox.shrink();
        }

        return Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                const Color(0xFF0F0F0F).withOpacity(0.95),
                const Color(0xFF0F0F0F),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                // Progress bar
                _buildProgressBar(audioPlayer),
                const SizedBox(height: 24),

                // Track info and controls
                Row(
                  children: [
                    // Album art
                    if (track.coverArtUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          track.coverArtUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildPlaceholderArt();
                          },
                        ),
                      )
                    else
                      _buildPlaceholderArt(),

                    const SizedBox(width: 24),

                    // Track info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.folderPath.isNotEmpty
                                ? track.folderPath
                                : 'Unknown Artist',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[400],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 32),

                    // Playback controls
                    _buildControls(audioPlayer),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderArt() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.music_note,
        color: Colors.white54,
        size: 40,
      ),
    );
  }

  Widget _buildProgressBar(AudioPlayerService audioPlayer) {
    final position = audioPlayer.position ?? Duration.zero;
    final duration = audioPlayer.duration ?? Duration.zero;
    final progress = duration.inSeconds > 0
        ? position.inSeconds / duration.inSeconds
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.grey[700],
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[400],
                ),
              ),
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls(AudioPlayerService audioPlayer) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Shuffle button
        _TvControlButton(
          icon: Icons.shuffle,
          isActive: audioPlayer.isShuffleEnabled,
          onPressed: () => audioPlayer.toggleShuffle(),
          size: 48,
        ),

        const SizedBox(width: 16),

        // Previous button
        _TvControlButton(
          icon: Icons.skip_previous,
          onPressed: audioPlayer.playPrevious,
          size: 56,
        ),

        const SizedBox(width: 16),

        // Play/Pause button (larger)
        _TvControlButton(
          icon: audioPlayer.isPlaying ? Icons.pause : Icons.play_arrow,
          onPressed: audioPlayer.togglePlayPause,
          size: 72,
          isPrimary: true,
        ),

        const SizedBox(width: 16),

        // Next button
        _TvControlButton(
          icon: Icons.skip_next,
          onPressed: audioPlayer.playNext,
          size: 56,
        ),

        const SizedBox(width: 16),

        // Repeat button
        _TvControlButton(
          icon: _getRepeatIcon(audioPlayer.repeatMode),
          isActive: audioPlayer.repeatMode != RepeatMode.off,
          onPressed: audioPlayer.toggleRepeatMode,
          size: 48,
        ),
      ],
    );
  }

  IconData _getRepeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return Icons.repeat;
      case RepeatMode.all:
        return Icons.repeat;
      case RepeatMode.one:
        return Icons.repeat_one;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// TV-optimized control button with focus support
class _TvControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final bool isActive;
  final bool isPrimary;

  const _TvControlButton({
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.isActive = false,
    this.isPrimary = false,
  });

  @override
  State<_TvControlButton> createState() => _TvControlButtonState();
}

class _TvControlButtonState extends State<_TvControlButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? Colors.white
                : widget.isActive
                    ? const Color(0xFF2D5F9F)
                    : const Color(0xFF2A2A2A),
            shape: BoxShape.circle,
            border: _isFocused
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: Icon(
            widget.icon,
            size: widget.size * 0.5,
            color: widget.isPrimary ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
