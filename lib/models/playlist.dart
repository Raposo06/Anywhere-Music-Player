import 'cover_art_ref.dart';

/// A server-side playlist, as Navidrome holds it.
///
/// Distinct from the *play queue* and from `PlaybackCursor`'s "playlist" (the
/// browsing context currently feeding playback) — this one is user-created,
/// named, stored on the server, and shared with the web UI. See
/// docs/decisions.md.
class Playlist with CoverArtRef {
  final String id;
  final String name;
  final int songCount;
  final int durationSeconds;

  /// Who owns it on the server. Subsonic only lets the **owner** modify a
  /// playlist, so this is what [isEditableBy] checks — a public playlist
  /// belonging to someone else is visible but not yours to change.
  final String? owner;

  final bool isPublic;

  /// The server's own verdict on whether this playlist can be edited, from
  /// OpenSubsonic's `readonly` field.
  ///
  /// Authoritative where [owner] is only a guess: Navidrome sets it for smart
  /// playlists (`.nsp`), for playlists belonging to someone else, and for
  /// anything else it considers non-editable. Absent on servers that predate
  /// the field, in which case ownership is all we have.
  final bool readonly;

  @override
  final String? coverArtId;

  const Playlist({
    required this.id,
    required this.name,
    this.songCount = 0,
    this.durationSeconds = 0,
    this.owner,
    this.isPublic = false,
    this.readonly = false,
    this.coverArtId,
  });

  factory Playlist.fromSubsonic(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'].toString(),
      name: json['name'] as String? ?? 'Untitled',
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration'] as num?)?.toInt() ?? 0,
      owner: json['owner'] as String?,
      isPublic: json['public'] as bool? ?? false,
      readonly: json['readonly'] as bool? ?? false,
      coverArtId: json['coverArt']?.toString(),
    );
  }

  /// Whether [username] may add to, remove from, rename or delete this.
  ///
  /// [readonly] wins when the server sends it — it is the server's own answer,
  /// and it is the only way to detect a Navidrome **smart playlist** (`.nsp`),
  /// which is read-only even to its owner. Editing one otherwise fails
  /// server-side and surfaces as an error after the fact.
  ///
  /// Falling back, unknown ownership is treated as editable: the server is the
  /// real authority and will refuse if we're wrong, whereas hiding the controls
  /// on a playlist the user *can* edit is a silent dead end.
  bool isEditableBy(String? username) {
    if (readonly) return false;
    return owner == null || username == null || owner == username;
  }

  /// e.g. "12 tracks · 48 min", or "1 track" — the subtitle every list shows.
  String get summary {
    final tracks = songCount == 1 ? '1 track' : '$songCount tracks';
    if (durationSeconds <= 0) return tracks;
    final minutes = durationSeconds ~/ 60;
    if (minutes < 60) return '$tracks · $minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$tracks · ${hours}h' : '$tracks · ${hours}h ${rest}m';
  }
}
