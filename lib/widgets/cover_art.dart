import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cover_art_ref.dart';
import '../services/auth_service.dart';
import '../services/stream_url_resolver.dart';

/// Renders a [Track] or [Folder]'s cover art at [size] logical pixels.
///
/// Hides the facts every render site used to restate by hand: multiplying
/// [size] by the device pixel ratio and passing that same rounded value to
/// both the URL and the cache key (so they can't fall out of step — the same
/// failure mode docs/decisions.md documents for the Android stream cache,
/// keying an image cache on a URL that silently changes), the null check,
/// the rounded clip, and the fallback icon for the loading/error states.
/// Resolves the URL itself via the live [AuthService.apiService] — callers
/// only ever need to say what and how big.
class CoverArt extends StatelessWidget {
  final CoverArtRef source;
  final double size;

  /// Pass true when this should fill its parent (e.g. inside `Expanded`)
  /// instead of being a fixed [size] box. The network request still asks for
  /// [size] regardless — a stable, layout-independent request so resizing
  /// the surrounding layout doesn't churn the image cache.
  final bool expand;

  final double radius;
  final IconData fallbackIcon;
  final Color? fallbackIconColor;

  /// Defaults to [size]; override when the fallback icon shouldn't scale
  /// with the (possibly much larger, in [expand] mode) request size.
  final double? fallbackIconSize;

  /// Whether the fallback icon shows while the image is loading, not just on
  /// error. Existing call sites disagree on this (folder tiles show it both
  /// ways; track tiles only on error, staying blank while loading) — no
  /// single default fits both.
  final bool showPlaceholder;

  /// Test-only: bypass the AuthService/Provider lookup with a fixed
  /// resolver, so a widget test can exercise real URL resolution without a
  /// logged-in AuthService in the tree.
  @visibleForTesting
  final StreamUrlResolver? resolverForTest;

  const CoverArt(
    this.source, {
    super.key,
    required this.size,
    this.expand = false,
    this.radius = 4,
    this.fallbackIcon = Icons.music_note,
    this.fallbackIconColor,
    this.fallbackIconSize,
    this.showPlaceholder = true,
    this.resolverForTest,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackIconWidget = Icon(
      fallbackIcon,
      size: fallbackIconSize ?? size,
      color: fallbackIconColor,
    );
    final fallback = expand ? Center(child: fallbackIconWidget) : fallbackIconWidget;

    final pixelSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final StreamUrlResolver? resolver =
        resolverForTest ?? context.watch<AuthService>().apiService;
    final url = resolver.resolveCoverUrl(source, size: pixelSize);
    if (url == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        cacheKey: source.coverCacheKey(size: pixelSize),
        width: expand ? null : size,
        height: expand ? null : size,
        fit: BoxFit.cover,
        placeholder: showPlaceholder ? (_, _) => fallback : null,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
