import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
// `RepeatMode` collides with Flutter's own (unrelated) animation-builder
// symbol added in 3.47 — hide it so this app's enum resolves. See
// docs/operations.md.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../services/auth_service.dart';
import '../../services/library_scanner.dart';
import '../../services/stream_url_resolver.dart';
import '../../utils/now_playing_folder.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/desktop/desktop_primitives.dart';
import '../../widgets/desktop/desktop_shortcuts.dart';
import '../../widgets/favourite_button.dart';
import '../../widgets/desktop/up_next_panel.dart';
import '../../widgets/desktop/window_chrome.dart';

/// The size the cover is *requested* at — deliberately a constant, and
/// deliberately larger than the biggest size it is ever drawn at
/// ([_maxArtDisplaySize]).
///
/// The art scales with the window, but the request must not: a size that
/// tracked the layout would mint a new URL and a new cache key on every
/// resize, re-downloading the same cover repeatedly. One oversized fetch,
/// scaled down to fit, costs a few KB instead. The precache below uses this
/// same constant, so the warmed cache key and the rendered one can't drift.
const _artRequestSize = 800.0;

/// Layout bounds for the left pane. The design fixes the art at 320px and the
/// info column at 380px, which is right at its 1240px reference width but
/// strands a lot of space on a large monitor — so both grow with the pane and
/// stop before the art starts dwarfing the controls beside it.
///
/// The minimums are what keeps art and info side by side rather than stacked
/// (see the [Wrap] below), so they are set as low as the content stays legible
/// at, not at a comfortable size — the pane is narrow when they bind. The art's
/// maximum is [_artRequestSize]: past that it would be upscaled from the fetch.
const _minArtDisplaySize = 200.0;
const _maxArtDisplaySize = _artRequestSize;
const _minInfoWidth = 300.0;
const _maxInfoWidth = 820.0;

/// Share of the pane the art takes, and the share of the pane's *height* it is
/// additionally capped at. 0.38 is the ratio the design's own 320px art
/// occupies at its reference width; the height cap is what stops a short, wide
/// window producing a cover taller than the space it sits in.
const _artWidthFraction = 0.38;
const _artHeightFraction = 0.72;

/// Gap between the art and the info column, and the pane's padding. All three
/// tighten on a narrow pane — at 48px they eat a third of the width there,
/// which is the difference between fitting side by side and stacking.
const _paneGap = 48.0;
const _paneHPadding = 48.0;
const _paneVPadding = 32.0;
const _minPaneGap = 24.0;
const _minPaneHPadding = 24.0;

/// Pane width below which the gap and padding scale down to their minimums.
const _tightPaneWidth = 900.0;

/// What [DesktopPlayerScreen] pops with when the user clicks through to the
/// track's folder.
///
/// The player covers the whole window from the *root* navigator, so it can't
/// push into the shell's library navigator itself. It closes and hands the
/// destination back instead, and the shell — which owns that navigator — does
/// the pushing. A plain pop (null) just closes the player.
typedef FolderRequest = ({String path, String name});

/// Full-window playback view: art and transport on the left, a permanent
/// "Up Next" queue on the right.
///
/// Covers the whole window (it is pushed on the *root* navigator, outside
/// [DesktopShell]), which is why it draws its own [WindowChrome] — with a back
/// chevron where the app mark usually sits.
class DesktopPlayerScreen extends StatefulWidget {
  const DesktopPlayerScreen({super.key});

  @override
  State<DesktopPlayerScreen> createState() => _DesktopPlayerScreenState();
}

class _DesktopPlayerScreenState extends State<DesktopPlayerScreen> {
  /// Track id we most recently kicked off an upcoming-cover precache for, so
  /// repeated rebuilds for the same track don't re-fetch.
  String? _precachedForTrackId;

  /// Last playback error shown in a SnackBar, so the same error isn't
  /// re-shown on every rebuild while it's still the current error.
  String? _shownError;

  /// How many upcoming covers to prefetch. Covers are KB, so a wide window is
  /// cheap and means rapid skip-forward lands on art already fetched.
  static const int _coverPrefetchAhead = 10;

  /// Prefetch the covers of upcoming tracks at player size so a rapid
  /// skip-forward lands on already-fetched art instead of an empty frame. The
  /// immediate next is fully decoded; the rest of the window is only
  /// downloaded to the image disk cache (no decode, so no pressure on the
  /// bounded in-memory cache). Fire-and-forget.
  void _precacheUpcomingCovers() {
    final ps = context.read<AudioPlayerService>();
    final current = ps.currentTrack;
    if (current == null || _precachedForTrackId == current.id) return;
    _precachedForTrackId = current.id;

    final StreamUrlResolver? resolver = context.read<AuthService>().apiService;
    final pixelSize = (_artRequestSize * MediaQuery.devicePixelRatioOf(context))
        .round();

    // Immediate next (wrap-aware): decode it so the very next skip is instant.
    final next = ps.peekNextTrack();
    final nextUrl = next == null
        ? null
        : resolver.resolveCoverUrl(next, size: pixelSize);
    if (nextUrl != null) {
      precacheImage(
        CachedNetworkImageProvider(
          nextUrl,
          cacheKey: next!.coverCacheKey(size: pixelSize),
        ),
        context,
      ).catchError((_) {
        // Cache miss / network blip — the real fetch happens on render.
      });
    }

    // Window ahead (queued tracks first, then play-order context): download to
    // the disk cache so skipping several forward finds covers already fetched.
    final window = <Track>[
      ...ps.queue,
      ...ps.upcomingFromContext,
    ].take(_coverPrefetchAhead);
    for (final track in window) {
      final url = resolver.resolveCoverUrl(track, size: pixelSize);
      if (url != null) {
        _warmCoverToDisk(url, track.coverCacheKey(size: pixelSize));
      }
    }
  }

  Future<void> _warmCoverToDisk(String url, String? cacheKey) async {
    try {
      await DefaultCacheManager().downloadFile(url, key: cacheKey);
    } catch (_) {
      // Best-effort; the on-demand fetch covers a miss.
    }
  }

  void _openFolder(Track track) {
    if (track.folderPath.isEmpty) return;
    final displayName = track.folderName.isNotEmpty
        ? track.folderName
        : track.folderPath.split('/').last;
    // Close, and let the shell open the folder — see [FolderRequest].
    Navigator.of(
      context,
    ).pop<FolderRequest>((path: track.folderPath, name: displayName));
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, Track?>(
      selector: (_, ps) => ps.currentTrack,
      builder: (context, track, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _precacheUpcomingCovers();
        });
        // Must be the *builder's* context, not the State's: this runs while
        // the Selector element is building, and by then this State's own
        // build() has already returned — `context.select` on it would assert.
        _watchForErrors(context);

        // Resolve to the scan's copy so the folder line (and its tap-through)
        // uses the real filesystem path even when playback started from a
        // playlist, whose tracks carry tag-based paths.
        final resolved = track == null
            ? null
            : canonicalTrack(track, context.read<LibraryScanner>());

        return DesktopPlaybackShortcuts(
          // Alt+← / Escape back out of Now Playing — the same plain pop the
          // chrome's back chevron does, so it can't strand a FolderRequest.
          onBack: () => Navigator.of(context).pop(),
          child: Scaffold(
            backgroundColor: AppColors.win,
            body: Column(
              children: [
                WindowChrome(
                  label: resolved == null
                      ? appDisplayName
                      : '${resolved.title} — $appDisplayName',
                  onBack: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: resolved == null
                      ? const Center(
                          child: Text(
                            'No track playing',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : _Body(
                          track: resolved,
                          onOpenFolder: () => _openFolder(resolved),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Surface a playback error once, as a SnackBar.
  ///
  /// [context] must be the context currently building — see the call site.
  void _watchForErrors(BuildContext context) {
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
  }
}

class _Body extends StatelessWidget {
  final Track track;
  final VoidCallback onOpenFolder;

  const _Body({required this.track, required this.onOpenFolder});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            // The accent bloom in the top-left corner from the design.
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6, -0.7),
                radius: 1.1,
                colors: [Color(0x1A00B2BD), AppColors.win],
                stops: [0.0, 0.55],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Gap and padding are the first things to give on a narrow
                // pane — see [_tightPaneWidth].
                final tightness = (constraints.maxWidth / _tightPaneWidth)
                    .clamp(0.0, 1.0);
                final gap = _minPaneGap + (_paneGap - _minPaneGap) * tightness;
                final hPadding =
                    _minPaneHPadding +
                    (_paneHPadding - _minPaneHPadding) * tightness;

                final available = constraints.maxWidth - hPadding * 2;
                final height = math.max(
                  0.0,
                  constraints.maxHeight - _paneVPadding * 2,
                );

                // The art tracks the pane's width but is also capped by its
                // height — see [_artWidthFraction]. This reproduces the mock
                // at its reference width and grows from there.
                final wanted = math
                    .min(
                      available * _artWidthFraction,
                      height * _artHeightFraction,
                    )
                    .clamp(_minArtDisplaySize, _maxArtDisplaySize);

                // Whatever's left goes to the controls, within bounds — past
                // ~820px the 34px title and the transport row just drift apart.
                final infoWidth = (available - wanted - gap).clamp(
                  _minInfoWidth,
                  _maxInfoWidth,
                );

                // On a wide pane the info column caps out well before the pane
                // runs out, which used to leave a band of empty pane beside a
                // cluster sized for a much smaller window. The art takes that
                // slack instead — still bounded by the pane's height and by
                // [_maxArtDisplaySize], so it can't outgrow the fetch or the
                // controls beside it.
                final artSize = math
                    .min(
                      available - infoWidth - gap,
                      height * _artHeightFraction,
                    )
                    .clamp(wanted, _maxArtDisplaySize);

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: hPadding,
                    vertical: _paneVPadding,
                  ),
                  // The scroll view sizes to its child, so [Center] alone would
                  // only centre horizontally and leave the cluster pinned to
                  // the top of a tall pane. Floor the child at the pane's
                  // height to centre it vertically too — and only floor it, so
                  // content taller than the pane still scrolls.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: height),
                    // Wrap, not Row: when the pane is too narrow for both at
                    // their minimums, they stack instead of overflowing.
                    child: Center(
                      child: Wrap(
                        spacing: gap,
                        runSpacing: 32,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _AlbumArt(
                            track: track,
                            size: artSize,
                            onTap: onOpenFolder,
                          ),
                          SizedBox(
                            width: infoWidth,
                            child: _Details(
                              track: track,
                              onOpenFolder: onOpenFolder,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const UpNextPanel(),
      ],
    );
  }
}

class _AlbumArt extends StatelessWidget {
  final Track track;
  final double size;
  final VoidCallback onTap;

  const _AlbumArt({
    required this.track,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final art = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.albumArt,
      ),
      // Drawn at [size], but fetched at the constant [_artRequestSize] — see
      // its doc for why those are deliberately different.
      child: CoverArt(
        track,
        size: _artRequestSize,
        expand: true,
        radius: 14,
        fallbackIconSize: 72,
        fallbackIconColor: AppColors.faint,
      ),
    );

    // Only clickable when there's a folder line to match — root-level tracks,
    // and tracks whose only path segment is the top-level category, shouldn't
    // pretend otherwise.
    if (nowPlayingFolderPath(track).isEmpty) return art;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: art),
    );
  }
}

class _Details extends StatelessWidget {
  final Track track;
  final VoidCallback onOpenFolder;

  const _Details({required this.track, required this.onOpenFolder});

  /// The artist to display, or null when there's nothing meaningful — an empty
  /// tag or Navidrome's '[Unknown Artist]' placeholder is treated as "no
  /// artist" so the line is hidden entirely.
  String? get _artist {
    final artist = track.artist?.trim();
    if (artist == null ||
        artist.isEmpty ||
        artist.toLowerCase() == '[unknown artist]') {
      return null;
    }
    return artist;
  }

  @override
  Widget build(BuildContext context) {
    final duration = track.durationSeconds != null
        ? Duration(seconds: track.durationSeconds!)
        : Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                track.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(width: 12),
            // Nudged down to sit on the title's first line rather than its
            // cap-height top, which a bare start-alignment lands on.
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FavouriteButton(track: track, size: 22),
            ),
          ],
        ),
        // Album is omitted: it's almost always the same as the folder below.
        if (_artist case final artist?) ...[
          const SizedBox(height: 8),
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, color: AppColors.muted),
          ),
        ],
        if (nowPlayingFolderPath(track) case final folderLine
            when folderLine.isNotEmpty) ...[
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onOpenFolder,
              child: Text(
                folderLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.accentText,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _ScrubBar(duration: duration),
        const SizedBox(height: 20),
        const _Transport(),
        const SizedBox(height: 20),
        const _ShuffleRepeatRow(),
        const SizedBox(height: 16),
        const _VolumeRow(),
        const SizedBox(height: 8),
        const _PlaylistPosition(),
      ],
    );
  }
}

/// The scrub bar: a slim accent track with a small round handle, elapsed and
/// total time beneath it.
class _ScrubBar extends StatefulWidget {
  final Duration duration;

  const _ScrubBar({required this.duration});

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<_ScrubBar> {
  // While dragging, the bar and its label follow [_dragValue] (a 0..1
  // fraction) instead of the position stream — this keeps the handle glued to
  // the pointer and avoids stream-vs-gesture jitter. [_dragStartTrackId] is
  // captured at drag start so the seek is discarded if the track
  // auto-advanced mid-drag.
  bool _isDragging = false;
  double _dragValue = 0;
  String? _dragStartTrackId;

  void _onChangeStart(double value) {
    setState(() {
      _isDragging = true;
      _dragValue = value;
      _dragStartTrackId = context.read<AudioPlayerService>().currentTrack?.id;
    });
  }

  void _onChangeEnd(double value) {
    final ps = context.read<AudioPlayerService>();
    final sameTrack = ps.currentTrack?.id == _dragStartTrackId;
    setState(() {
      _isDragging = false;
      _dragStartTrackId = null;
    });
    if (sameTrack && widget.duration > Duration.zero) {
      ps.seek(
        Duration(
          milliseconds: (value * widget.duration.inMilliseconds).round(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.read<AudioPlayerService>();
    final hasDuration = widget.duration > Duration.zero;

    return StreamBuilder<Duration>(
      stream: playerService.positionStream,
      builder: (context, snapshot) {
        final streamPosition = snapshot.data ?? Duration.zero;
        final fraction = _isDragging
            ? _dragValue
            : (hasDuration
                  ? streamPosition.inMilliseconds /
                        widget.duration.inMilliseconds
                  : 0.0);
        final position = _isDragging
            ? Duration(
                milliseconds: (_dragValue * widget.duration.inMilliseconds)
                    .round(),
              )
            : streamPosition;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                // The design's bar runs the full width of the info column;
                // Slider's default padding would inset it.
                padding: EdgeInsets.zero,
              ),
              child: Slider(
                value: fraction.clamp(0.0, 1.0),
                onChanged: hasDuration
                    ? (value) => setState(() => _dragValue = value)
                    : null,
                onChangeStart: hasDuration ? _onChangeStart : null,
                onChangeEnd: hasDuration ? _onChangeEnd : null,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatPlaybackDuration(position),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                Text(
                  formatPlaybackDuration(widget.duration),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) {
    final playerService = context.read<AudioPlayerService>();

    return Selector<AudioPlayerService, int>(
      selector: (_, ps) => ps.playlist.length,
      builder: (context, playlistLength, _) {
        final canSkip = playlistLength > 1;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TransportButton(
              icon: Icons.skip_previous,
              size: 26,
              tooltip: 'Previous (Ctrl+←)',
              onPressed: canSkip ? playerService.playPrevious : null,
            ),
            const SizedBox(width: 22),
            StreamBuilder<bool>(
              stream: playerService.playingStream,
              initialData: playerService.isPlaying,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                return AccentCircleButton(
                  size: 60,
                  glow: true,
                  icon: isPlaying ? Icons.pause : Icons.play_arrow,
                  tooltip: isPlaying ? 'Pause (Space)' : 'Play (Space)',
                  onPressed: playerService.togglePlayPause,
                );
              },
            ),
            const SizedBox(width: 22),
            TransportButton(
              icon: Icons.skip_next,
              size: 26,
              tooltip: 'Next (Ctrl+→)',
              onPressed: canSkip ? playerService.playNext : null,
            ),
          ],
        );
      },
    );
  }
}

/// The labelled shuffle and repeat toggles beneath the transport row.
class _ShuffleRepeatRow extends StatelessWidget {
  const _ShuffleRepeatRow();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, ({bool shuffle, RepeatMode repeat})>(
      selector: (_, ps) =>
          (shuffle: ps.isShuffleEnabled, repeat: ps.repeatMode),
      builder: (context, state, _) {
        final playerService = context.read<AudioPlayerService>();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ToggleLabel(
              icon: Icons.shuffle,
              label: state.shuffle ? 'Shuffle ON' : 'Shuffle OFF',
              active: state.shuffle,
              onTap: playerService.toggleShuffle,
            ),
            const SizedBox(width: 28),
            _ToggleLabel(
              icon: state.repeat == RepeatMode.one
                  ? Icons.repeat_one
                  : Icons.repeat,
              label: switch (state.repeat) {
                RepeatMode.off => 'Repeat OFF',
                RepeatMode.all => 'Repeat ALL',
                RepeatMode.one => 'Repeat ONE',
              },
              active: state.repeat != RepeatMode.off,
              onTap: playerService.toggleRepeatMode,
            ),
          ],
        );
      },
    );
  }
}

/// An icon-plus-text toggle: faint when off, accent and bold when on.
class _ToggleLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleLabel({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: active ? AppColors.accent : AppColors.faint,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: active ? AppColors.accentText : AppColors.faint,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, double>(
      selector: (_, ps) => ps.volume,
      builder: (context, volume, _) {
        return Row(
          children: [
            Icon(
              volume == 0
                  ? Icons.volume_off
                  : volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
              size: 16,
              color: AppColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Slider(
                  value: volume,
                  divisions: 20,
                  label: '${(volume * 100).round()}%',
                  onChanged: context.read<AudioPlayerService>().setVolume,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 36,
              child: Text(
                '${(volume * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistPosition extends StatelessWidget {
  const _PlaylistPosition();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerService, ({int index, int length})>(
      selector: (_, ps) => (index: ps.currentIndex, length: ps.playlist.length),
      builder: (context, state, _) {
        if (state.length <= 1) return const SizedBox.shrink();
        return Text(
          'Track ${state.index + 1} of ${state.length}',
          style: const TextStyle(fontSize: 12, color: AppColors.faint),
        );
      },
    );
  }
}
