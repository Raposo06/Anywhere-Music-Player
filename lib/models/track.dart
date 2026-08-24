import 'cover_art_ref.dart';

class Track with CoverArtRef {
  final String id;
  final String title;
  /// Full library-relative file path (e.g. "Artist/Album/song.flac") — not a
  /// bare filename, despite the field's history. Empty when the source
  /// didn't provide one (rather than a synthesized placeholder), which is
  /// also what [folderPath] and [folderName] default to for the same reason.
  final String path;
  @override
  final String? coverArtId;
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
    required this.path,
    this.coverArtId,
    required this.folderPath,
    this.folderName = '',
    this.durationSeconds,
    this.fileSizeBytes,
    required this.createdAt,
    this.artist,
    this.album,
    this.replayGainDb,
  });

  /// Create a Track from a Subsonic API (`/rest/*`) song response. Doesn't
  /// take a [StreamUrlResolver] — nothing here needs one; [streamUrl] and
  /// [coverArtUrl] are resolved at the moment of use instead (see
  /// StreamUrlResolver).
  factory Track.fromSubsonic(Map<String, dynamic> json, {String? parentFolderName}) {
    final songId = json['id'].toString();
    final coverArtId = json['coverArt']?.toString();
    final filePath = json['path'] as String?;
    final extractedFolderPath = _extractFolderPath(filePath);

    return Track(
      id: songId,
      title: json['title'] as String? ?? 'Unknown',
      path: filePath ?? '',
      coverArtId: coverArtId,
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

  /// Create a Track from a Navidrome native-API (`/api/song`) response.
  /// A separate factory, not a variant of [fromSubsonic]: the native API
  /// isn't Subsonic-shaped, it uses different key names for the same
  /// concepts (`coverArtId` vs `coverArt`, `rgTrackGain` vs
  /// `replayGain.trackGain`, `createdAt` vs `created`) because it's a
  /// different endpoint on the same server, not just a different transport.
  /// Used by [LibraryScanner], which fetches the whole library through this
  /// endpoint for its real filesystem paths (the Subsonic API only exposes
  /// tag-based virtual paths).
  factory Track.fromNativeApi(Map<String, dynamic> json) {
    final songId = json['id']?.toString() ?? '';
    final coverArtId = json['coverArtId']?.toString() ?? json['id']?.toString();
    final filePath = json['path'] as String?;
    final extractedFolderPath = _extractFolderPath(filePath);

    return Track(
      id: songId,
      title: json['title'] as String? ?? 'Unknown',
      path: filePath ?? '',
      coverArtId: coverArtId,
      folderPath: extractedFolderPath,
      folderName: _lastSegment(extractedFolderPath),
      durationSeconds: (json['duration'] is num) ? (json['duration'] as num).round() : null,
      fileSizeBytes: (json['size'] is num) ? (json['size'] as num).round() : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      replayGainDb: (json['rgTrackGain'] as num?)?.toDouble(),
    );
  }

  /// Reconstruct a Track from its [toJson] representation (used by the
  /// on-disk library cache).
  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id:               json['id'] as String,
      title:            json['title'] as String,
      path:             json['path'] as String,
      coverArtId:      (json['cover_art_id'] as String?),
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
    'path': path,
    // stream_url / cover_art_url are never persisted, and never held at all
    // any more — both carry a live auth token+salt, minted fresh from `id` /
    // `cover_art_id` at the moment of use instead. See StreamUrlResolver.
    'cover_art_id': coverArtId,
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

  // coverCacheKey comes from CoverArtRef. streamUrl/coverUrl are resolved at
  // the point of use via StreamUrlResolver, not carried on the model.
}
