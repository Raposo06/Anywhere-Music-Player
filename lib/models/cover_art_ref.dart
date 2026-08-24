/// Shared identity for anything that can be shown as cover art — a `Track`
/// or a `Folder`. Both derive a stable cache key from the same `coverArtId`;
/// this mixin is the one place that logic lives, instead of two identical
/// copies. The actual cover-art URL isn't part of this — see
/// StreamUrlResolver, consulted at the moment of use, not carried here.
mixin CoverArtRef {
  /// Raw Subsonic cover art id (stable, unlike the resolved URL, whose auth
  /// salt rotates on every request). Used to build a stable cache key for
  /// image caching instead of keying on the ever-changing URL, and to
  /// resolve a URL on demand via StreamUrlResolver.
  String? get coverArtId;

  /// Stable cache key for the cover at a given [size], derived from the
  /// unchanging [coverArtId] rather than the resolved URL (whose auth salt
  /// rotates on every rebuild). Pass this as the `cacheKey`/`key` argument to
  /// CachedNetworkImage / flutter_cache_manager so re-scans don't invalidate
  /// already-downloaded art. Returns null when there's no cover.
  String? coverCacheKey({int? size}) {
    final id = coverArtId;
    if (id == null) return null;
    return 'cover_${id}_${size ?? 'full'}';
  }
}
