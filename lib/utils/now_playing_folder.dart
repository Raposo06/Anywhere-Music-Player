import '../models/track.dart';
import '../services/library_scanner.dart';

/// The track the library scan holds for [playing] — the copy carrying a real
/// filesystem path — or [playing] unchanged when the scan doesn't have it.
///
/// Playlist playback builds tracks from the Subsonic API, whose `path` is a
/// tag-based virtual path ("AlbumArtist/Album"); the scan's copy has the real
/// path. Resolving by id here is what keeps Now Playing — and its tap-through
/// to the folder — consistent regardless of how playback started.
Track canonicalTrack(Track playing, LibraryScanner scanner) =>
    scanner.trackById(playing.id) ?? playing;

/// The folder path to show on Now Playing: the real path with its top-level
/// segment dropped (a broad category like "SOUNDTRACKS" that's shared across
/// much of the library and adds nothing here). Empty when nothing is left —
/// the folder line then hides entirely.
String nowPlayingFolderPath(Track canonical) {
  final segments = canonical.folderPath.split('/');
  return segments.length <= 1 ? '' : segments.sublist(1).join('/');
}
