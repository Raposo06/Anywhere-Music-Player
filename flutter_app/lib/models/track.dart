import '../services/subsonic_api_service.dart';

class Track {
  final String id;
  final String title;
  final String filename;
  final String streamUrl;
  final String? coverArtUrl;
  final String folderPath;
  final String folderName;
  final int? durationSeconds;
  final int? fileSizeBytes;
  final DateTime createdAt;
  final String? artist;
  final String? album;

  Track({
    required this.id,
    required this.title,
    required this.filename,
    required this.streamUrl,
    this.coverArtUrl,
    required this.folderPath,
    this.folderName = '',
    this.durationSeconds,
    this.fileSizeBytes,
    required this.createdAt,
    this.artist,
    this.album,
  });

  /// Create a Track from a Subsonic API song response.
  factory Track.fromSubsonic(Map<String, dynamic> json, SubsonicApiService api, {String? parentFolderName}) {
    final songId = json['id'].toString();
    final coverArtId = json['coverArt']?.toString();
    final filePath = json['path'] as String?;
    final extractedFolderPath = _extractFolderPath(filePath);

    return Track(
      id: songId,
      title: json['title'] as String? ?? 'Unknown',
      filename: filePath ?? '${json['title'] ?? 'unknown'}.${json['suffix'] ?? 'mp3'}',
      streamUrl: api.buildStreamUrl(songId),
      coverArtUrl: coverArtId != null ? api.buildCoverArtUrl(coverArtId) : null,
      folderPath: extractedFolderPath,
      folderName: parentFolderName ?? _lastSegment(extractedFolderPath),
      durationSeconds: json['duration'] as int?,
      fileSizeBytes: json['size'] as int?,
      createdAt: json['created'] != null
          ? DateTime.tryParse(json['created'] as String) ?? DateTime.now()
          : DateTime.now(),
      artist: json['artist'] as String?,
      album: json['album'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filename': filename,
    'stream_url': streamUrl,
    'cover_art_url': coverArtUrl,
    'folder_path': folderPath,
    'folder_name': folderName,
    'duration_seconds': durationSeconds,
    'file_size_bytes': fileSizeBytes,
    'created_at': createdAt.toIso8601String(),
    'artist': artist,
    'album': album,
  };

  static String _lastSegment(String path) {
    if (path.isEmpty) return '';
    final parts = path.split('/');
    return parts.last;
  }

  static String _extractFolderPath(String? path) {
    if (path == null || !path.contains('/')) return '';
    return path.substring(0, path.lastIndexOf('/'));
  }

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
