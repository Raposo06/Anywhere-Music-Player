import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/auth_service.dart';
import '../services/stream_url_resolver.dart';

/// Warms the covers of the tracks *after* the current one, so a rapid
/// skip-forward lands on art already fetched instead of an empty frame.
///
/// Hold one per player screen and call [precache] from a post-frame callback
/// after each build. The immediate next track's cover is fully decoded (so the
/// very next skip is instant); the rest of a short window is only downloaded to
/// the image disk cache — no decode, so no pressure on the bounded in-memory
/// cache. All best-effort: a miss just means the on-demand fetch runs on
/// render. A no-op until the current track changes.
///
/// [logicalSize] must be the size the screen actually renders the cover at, so
/// the warmed URL and cache key match what the render asks for — a mismatch is
/// a silent 100% miss. The phone passes its responsive art size; the desktop
/// passes its fixed request constant (see that screen's own note on why the
/// request size must not track the window).
class UpcomingCoverPrecacher {
  /// How far ahead to warm. Covers are a few KB each, so a wide window is cheap
  /// and absorbs a burst of skips.
  static const int _windowAhead = 10;

  String? _warmedForTrackId;

  void precache(BuildContext context, {required double logicalSize}) {
    final player = context.read<AudioPlayerService>();
    final current = player.currentTrack;
    if (current == null || _warmedForTrackId == current.id) return;
    _warmedForTrackId = current.id;

    final StreamUrlResolver? resolver = context.read<AuthService>().apiService;
    final pixelSize =
        (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();

    // Immediate next (wrap-aware): decode it so the very next skip is instant.
    final next = player.peekNextTrack();
    final nextUrl =
        next == null ? null : resolver.resolveCoverUrl(next, size: pixelSize);
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
    final window = <Track>[...player.queue, ...player.upcomingFromContext]
        .take(_windowAhead);
    for (final track in window) {
      final url = resolver.resolveCoverUrl(track, size: pixelSize);
      if (url != null) {
        _warmToDisk(url, track.coverCacheKey(size: pixelSize));
      }
    }
  }

  Future<void> _warmToDisk(String url, String? cacheKey) async {
    try {
      await DefaultCacheManager().downloadFile(url, key: cacheKey);
    } catch (_) {
      // Best-effort; the on-demand fetch covers a miss.
    }
  }
}
