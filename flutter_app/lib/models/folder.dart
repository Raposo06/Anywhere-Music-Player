class Folder {
  final String? id;
  final String folderPath;
  final int trackCount;

  Folder({
    this.id,
    required this.folderPath,
    required this.trackCount,
  });

  /// Create a Folder from a Subsonic API directory/artist response.
  factory Folder.fromSubsonic(Map<String, dynamic> json) {
    // Count child songs (non-directory items) if available
    int childCount = 0;
    final childList = json['child'];
    if (childList != null) {
      final children = childList is List ? childList : [childList];
      childCount = children.where((c) => c['isDir'] != true).length;
    }
    // Fall back to albumCount for artist entries
    childCount = childCount > 0 ? childCount : (json['albumCount'] as int? ?? 0);

    return Folder(
      id: json['id']?.toString(),
      folderPath: json['name'] as String? ?? json['title'] as String? ?? 'Unknown',
      trackCount: childCount,
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
