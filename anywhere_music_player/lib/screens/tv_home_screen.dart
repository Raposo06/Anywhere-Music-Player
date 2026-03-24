import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/audio_player_service.dart';
import '../services/library_scanner.dart';
import '../models/track.dart';
import '../widgets/tv_player_controls.dart';

/// Android TV optimized home screen — simple "All Tracks" view with shuffle.
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  List<Track> _tracks = [];

  final _listScopeNode = FocusScopeNode(debugLabel: 'trackList');
  final _controlsScopeNode = FocusScopeNode(debugLabel: 'controls');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTracks();
    });
  }

  void _loadTracks() {
    final scanner = context.read<LibraryScanner>();
    if (!scanner.hasScanned) {
      scanner.addListener(_onScannerChanged);
      scanner.scan();
      return;
    }
    setState(() {
      _tracks = List<Track>.from(scanner.allTracks)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    });
  }

  void _onScannerChanged() {
    final scanner = context.read<LibraryScanner>();
    if (scanner.hasScanned) {
      scanner.removeListener(_onScannerChanged);
      setState(() {
        _tracks = List<Track>.from(scanner.allTracks)
          ..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      });
    }
  }

  @override
  void dispose() {
    _listScopeNode.dispose();
    _controlsScopeNode.dispose();
    super.dispose();
  }

  void _playTrack(int index) {
    final audioPlayer = context.read<AudioPlayerService>();
    audioPlayer.playPlaylist(_tracks, index);
  }

  void _shuffleAll() {
    if (_tracks.isEmpty) return;
    final audioPlayer = context.read<AudioPlayerService>();
    if (!audioPlayer.isShuffleEnabled) {
      audioPlayer.toggleShuffle();
    }
    audioPlayer.playPlaylist(_tracks, 0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: Stack(
          children: [
            SafeArea(
              child: FocusScope(
                node: _listScopeNode,
                child: FocusTraversalGroup(
                  child: _buildBody(),
                ),
              ),
            ),
            // Player controls overlay at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FocusScope(
                node: _controlsScopeNode,
                child: FocusTraversalGroup(
                  child: TvPlayerControls(
                    onNavigateUp: () => _listScopeNode.requestFocus(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with title and shuffle button
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 32, 48, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Anywhere Music',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_tracks.length} tracks',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              _TvShuffleButton(
                onPressed: _shuffleAll,
                onNavigateDown: () => _controlsScopeNode.requestFocus(),
                autofocus: _tracks.isNotEmpty,
              ),
            ],
          ),
        ),

        // Track list
        Expanded(
          child: _tracks.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 220),
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final track = _tracks[index];
                    return _TvTrackRow(
                      track: track,
                      onTap: () => _playTrack(index),
                      onNavigateDown: () {
                        // Jump to controls if at bottom of visible list
                        final didMove = Actions.invoke(
                          context,
                          DirectionalFocusIntent(TraversalDirection.down),
                        );
                        if (didMove == null) {
                          _controlsScopeNode.requestFocus();
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Large shuffle button for the TV header
class _TvShuffleButton extends StatefulWidget {
  final VoidCallback onPressed;
  final VoidCallback onNavigateDown;
  final bool autofocus;

  const _TvShuffleButton({
    required this.onPressed,
    required this.onNavigateDown,
    this.autofocus = false,
  });

  @override
  State<_TvShuffleButton> createState() => _TvShuffleButtonState();
}

class _TvShuffleButtonState extends State<_TvShuffleButton> {
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
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            widget.onNavigateDown();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : const Color(0xFF2D5F9F),
            borderRadius: BorderRadius.circular(32),
            border: _isFocused
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shuffle,
                size: 28,
                color: _isFocused ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                'Shuffle All',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _isFocused ? Colors.black : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TV-optimized track row with focus support
class _TvTrackRow extends StatefulWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onNavigateDown;

  const _TvTrackRow({
    required this.track,
    required this.onTap,
    required this.onNavigateDown,
  });

  @override
  State<_TvTrackRow> createState() => _TvTrackRowState();
}

class _TvTrackRowState extends State<_TvTrackRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final audioPlayer = context.watch<AudioPlayerService>();
    final isPlaying = audioPlayer.currentTrack?.id == widget.track.id;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isPlaying
                ? const Color(0xFF2D5F9F).withOpacity(0.3)
                : _isFocused
                    ? const Color(0xFF2A2A2A)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _isFocused
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: Row(
            children: [
              // Playing indicator or album art
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: isPlaying
                    ? const Icon(Icons.equalizer, color: Color(0xFF2D5F9F), size: 28)
                    : widget.track.coverArtUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: CachedNetworkImage(
                              imageUrl: widget.track.coverArtUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.music_note,
                                color: Colors.white54,
                                size: 24,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.music_note,
                            color: Colors.white54,
                            size: 24,
                          ),
              ),
              const SizedBox(width: 20),

              // Track title
              Expanded(
                child: Text(
                  widget.track.title,
                  style: TextStyle(
                    fontSize: 20,
                    color: isPlaying ? const Color(0xFF5B9BF0) : Colors.white,
                    fontWeight:
                        isPlaying ? FontWeight.bold : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Duration
              if (widget.track.durationSeconds != null)
                Text(
                  _formatDuration(widget.track.durationSeconds!),
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[500],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }
}
