class Track {
  final String id;
  final String title;
  final String filename;
  final String streamUrl;
  final String? coverArtUrl;
  final String folderPath;
  final int? durationSeconds;
  final int? fileSizeBytes;
  final DateTime createdAt;

  Track({
    required this.id,
    required this.title,
    required this.filename,
    required this.streamUrl,
    this.coverArtUrl,
    required this.folderPath,
    this.durationSeconds,
    this.fileSizeBytes,
    required this.createdAt,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      filename: json['filename'] as String,
      streamUrl: json['stream_url'] as String,
      coverArtUrl: json['cover_art_url'] as String?,
      folderPath: json['folder_path'] as String? ?? '',
      durationSeconds: json['duration_seconds'] as int?,
      fileSizeBytes: json['file_size_bytes'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filename': filename,
    'stream_url': streamUrl,
    'cover_art_url': coverArtUrl,
    'folder_path': folderPath,
    'duration_seconds': durationSeconds,
    'file_size_bytes': fileSizeBytes,
    'created_at': createdAt.toIso8601String(),
  };

  /// Format duration as MM:SS or H:MM:SS for 1 hour+ tracks
  String get formattedDuration {
    if (durationSeconds == null) return '--:--';
    final hours = durationSeconds! ~/ 3600;
    final minutes = (durationSeconds! % 3600) ~/ 60;
    final seconds = durationSeconds! % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Format file size as MB
  String get formattedFileSize {
    if (fileSizeBytes == null) return 'Unknown';
    final mb = fileSizeBytes! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
