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
  /// Track-level ReplayGain in dB from the server's loudness analysis, or null
  /// if the file hasn't been analyzed. Used to normalize playback volume.
  final double? replayGainDb;

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
    this.replayGainDb,
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
      replayGainDb:
          ((json['replayGain'] as Map<String, dynamic>?)?['trackGain'] as num?)
              ?.toDouble(),
    );
  }

  /// Reconstruct a Track from its [toJson] representation (used by the
  /// on-disk library cache). The streamUrl is intentionally NOT persisted —
  /// it's derived data (function of the server URL + auth + URL flags like
  /// `format=raw`). Recomputing it at load time means any future change to
  /// [SubsonicApiService.buildStreamUrl] propagates immediately without
  /// needing a cache version bump.
  factory Track.fromJson(Map<String, dynamic> json, {required SubsonicApiService api}) {
    final id = json['id'] as String;
    return Track(
      id:               id,
      title:            json['title'] as String,
      filename:         json['filename'] as String,
      streamUrl:        api.buildStreamUrl(id),
      coverArtUrl:      json['cover_art_url'] as String?,
      folderPath:       json['folder_path'] as String,
      folderName:      (json['folder_name'] as String?) ?? '',
      durationSeconds:  json['duration_seconds'] as int?,
      fileSizeBytes:    json['file_size_bytes'] as int?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      artist:           json['artist'] as String?,
      album:            json['album'] as String?,
      replayGainDb:     (json['replay_gain_db'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filename': filename,
    // stream_url deliberately omitted — recomputed from `id` in fromJson.
    'cover_art_url': coverArtUrl,
    'folder_path': folderPath,
    'folder_name': folderName,
    'duration_seconds': durationSeconds,
    'file_size_bytes': fileSizeBytes,
    'created_at': createdAt.toIso8601String(),
    'artist': artist,
    'album': album,
    'replay_gain_db': replayGainDb,
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

  /// Cover art URL for a given square pixel [size] (typically the rendered
  /// logical size × devicePixelRatio). Pass null for full resolution. Returns
  /// null when there's no cover. The stored [coverArtUrl] carries no size, so
  /// each caller requests exactly what it renders rather than one fixed size.
  String? coverUrl({int? size}) {
    final base = coverArtUrl;
    if (base == null) return null;
    return size == null ? base : '$base&size=$size';
  }
}
