import '../services/subsonic_api_service.dart';

class Folder {
  final String? id;
  final String folderPath;
  final int trackCount;
  final String? coverArtUrl;
  final int albumCount;

  Folder({
    this.id,
    required this.folderPath,
    required this.trackCount,
    this.coverArtUrl,
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
      coverArtUrl = api.buildCoverArtUrl(coverArtId, size: 256);
    }

    return Folder(
      id: json['id']?.toString(),
      folderPath: json['name'] as String? ?? json['title'] as String? ?? 'Unknown',
      trackCount: displayCount,
      coverArtUrl: coverArtUrl,
      albumCount: albumCnt,
    );
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
