class Folder {
  final String folderPath;
  final int trackCount;

  Folder({
    required this.folderPath,
    required this.trackCount,
  });

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      folderPath: json['folder_path'] as String,
      trackCount: json['track_count'] as int,
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
