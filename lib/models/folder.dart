import '../services/subsonic_api_service.dart';

class Folder {
  final String? id;
  final String folderPath;
  final int trackCount;
  final String? coverArtUrl;
  /// Raw Subsonic cover art id — see [Track.coverArtId] for why this is
  /// kept separately from the (salt-rotating) [coverArtUrl].
  final String? coverArtId;
  final int albumCount;

  Folder({
    this.id,
    required this.folderPath,
    required this.trackCount,
    this.coverArtUrl,
    this.coverArtId,
    this.albumCount = 0,
  });

  /// Create a Folder from a Subsonic API directory/artist response.
  /// Pass [api] to resolve cover art URLs.
  factory Folder.fromSubsonic(Map<String, dynamic> json, {SubsonicApiService? api}) {
    // Count direct child songs (non-directory items) if available
    int childCount = 0;
    final childList = json['child'];
    if (childList != null) {
      final children = childList is List ? childList : [childList];
      childCount = children.where((c) => c['isDir'] != true).length;
    }

    final albumCnt = json['albumCount'] as int? ?? 0;
    // Use child song count if available, otherwise fall back to albumCount
    final displayCount = childCount > 0 ? childCount : albumCnt;

    // Resolve cover art URL
    final coverArtId = json['coverArt']?.toString() ?? json['artistImageUrl']?.toString();
    String? coverArtUrl;
    if (coverArtId != null && api != null) {
      // Size-less base URL; callers append the size they render via [coverUrl].
      coverArtUrl = api.buildCoverArtUrl(coverArtId);
    }

    return Folder(
      id: json['id']?.toString(),
      folderPath: json['name'] as String? ?? json['title'] as String? ?? 'Unknown',
      trackCount: displayCount,
      coverArtUrl: coverArtUrl,
      coverArtId: coverArtId,
      albumCount: albumCnt,
    );
  }

  /// Cover art URL for a given square pixel [size] (typically the rendered
  /// logical size × devicePixelRatio). Pass null for full resolution. Returns
  /// null when there's no cover. The stored [coverArtUrl] carries no size.
  String? coverUrl({int? size}) {
    final base = coverArtUrl;
    if (base == null) return null;
    return size == null ? base : '$base&size=$size';
  }

  /// Stable cache key for the cover at a given [size] — see
  /// [Track.coverCacheKey] for rationale.
  String? coverCacheKey({int? size}) {
    final id = coverArtId;
    if (id == null) return null;
    return 'cover_${id}_${size ?? 'full'}';
  }

  /// Get the display name (last segment of path)
  /// e.g., "Animes/Pokemon" → "Pokemon"
  String get displayName {
    if (folderPath.contains('/')) {
      return folderPath.split('/').last;
    }
    return folderPath;
  }

  /// Subtitle text showing album or track count
  String get subtitle {
    if (trackCount > 0) return '$trackCount track(s)';
    if (albumCount > 0) return '$albumCount album(s)';
    return '';
  }

  /// Check if this is a root folder (no "/" in path)
  bool get isRoot => !folderPath.contains('/');

  /// Get the parent path
  /// e.g., "Animes/Pokemon" → "Animes"
  String? get parentPath {
    if (!folderPath.contains('/')) return null;
    final segments = folderPath.split('/');
    segments.removeLast();
    return segments.join('/');
  }
}
