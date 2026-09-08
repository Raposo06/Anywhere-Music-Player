import '../models/track.dart';
import '../services/library_scanner.dart';

/// The track the library scan holds for [playing] — the copy carrying a real
/// filesystem path — or [playing] unchanged when the scan doesn't have it.
///
/// Playlist playback builds tracks from the Subsonic API, whose `path` for a
/// playlist entry need not be the path the folder walk arrived at; the scan's
/// copy is the canonical one. Resolving by id here is what keeps Now Playing —
/// and its tap-through to the folder — consistent regardless of how playback
/// started.
Track canonicalTrack(Track playing, LibraryScanner scanner) =>
    scanner.trackById(playing.id) ?? playing;

/// The folder path to show on Now Playing: the track's real path in full.
///
/// This used to drop the first segment, back when the library sat under a
/// single `SOUNDTRACKS` root that was the same for almost every track and so
/// carried no information. The move to Gonic reshaped the tree — the top level
/// is now five sibling categories — which made the dropped segment meaningful
/// and blanked the line entirely for tracks sitting directly in one. See
/// docs/decisions.md.
///
/// Empty when the track has no folder at all, which still hides the line.
String nowPlayingFolderPath(Track canonical) => canonical.folderPath;
