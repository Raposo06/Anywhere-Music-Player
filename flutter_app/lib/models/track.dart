import 'package:json_annotation/json_annotation.dart';

part 'track.g.dart';

@JsonSerializable()
class Track {
  final String id;
  final String title;
  final String filename;

  @JsonKey(name: 'stream_url')
  final String streamUrl;

  @JsonKey(name: 'cover_art_url')
  final String? coverArtUrl;

  @JsonKey(name: 'folder_path')
  final String folderPath;

  @JsonKey(name: 'duration_seconds')
  final int? durationSeconds;

  @JsonKey(name: 'file_size_bytes')
  final int? fileSizeBytes;

  @JsonKey(name: 'created_at')
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

  factory Track.fromJson(Map<String, dynamic> json) => _$TrackFromJson(json);
  Map<String, dynamic> toJson() => _$TrackToJson(this);

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
