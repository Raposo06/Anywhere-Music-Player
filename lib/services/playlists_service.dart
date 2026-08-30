import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'subsonic_api_service.dart';

/// The user's server-side playlists.
///
/// Shaped like [FavouritesService]: constructed with the current
/// [SubsonicApiService] (null while logged out) and rebound by `MyApp`'s proxy
/// provider when the session changes, so it never outlives its session.
///
/// **Not optimistic**, unlike favourites. A playlist edit is a structural
/// change to shared, server-owned data — and Subsonic removes tracks by
/// *position*, so acting on a stale local copy can delete the wrong track.
/// Every mutation therefore waits for the server and then re-reads. See
/// docs/decisions.md.
class PlaylistsService with ChangeNotifier {
  final SubsonicApiService? _api;

  PlaylistsService(this._api);

  SubsonicApiService? get api => _api;

  final List<Playlist> _playlists = [];

  /// Tracks per playlist id, for the ones that have been opened. Playlists can
  /// be long and are rarely all needed at once, so contents are fetched on
  /// demand rather than eagerly with the list.
  final Map<String, List<Track>> _tracks = {};

  bool _loading = false;
  bool _loaded = false;
  String? _error;

  /// Playlist ids with an in-flight or completed content fetch, so a detail
  /// screen rebuilding doesn't re-request what it already asked for.
  final Set<String> _fetchingTracks = {};

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get isLoading => _loading;
  bool get isLoaded => _loaded;
  String? get error => _error;

  /// The tracks of [playlistId], or null if they haven't been fetched yet —
  /// which a detail screen shows as loading rather than as an empty playlist.
  List<Track>? tracksOf(String playlistId) => _tracks[playlistId];

  Playlist? byId(String playlistId) {
    for (final p in _playlists) {
      if (p.id == playlistId) return p;
    }
    return null;
  }

  /// Fetch the playlist list. Safe to call repeatedly; concurrent calls
  /// collapse into the first.
  Future<void> load() async {
    final api = _api;
    if (api == null || _loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await api.getPlaylists();
      _playlists
        ..clear()
        ..addAll(result);
      _loaded = true;
    } catch (e) {
      _error = 'Could not load playlists: $e';
      debugPrint('PlaylistsService: load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Fetch [playlistId]'s tracks.
  ///
  /// Pass [force] after a mutation; otherwise an already-fetched playlist is
  /// left alone so opening it repeatedly costs nothing.
  Future<void> loadTracks(String playlistId, {bool force = false}) async {
    final api = _api;
    if (api == null) return;
    if (!force && _fetchingTracks.contains(playlistId)) return;
    _fetchingTracks.add(playlistId);

    try {
      final result = await api.getPlaylist(playlistId);
      _tracks[playlistId] = result.tracks;
      // The list's copy carries a stale song count after an edit; the detail
      // fetch is authoritative, so fold it back in. When the playlist isn't
      // in the list at all — a detail view opened before (or without) a
      // load() — keep it rather than dropping it, or `byId` stays null and
      // the screen cannot tell whether the playlist is editable.
      final index = _playlists.indexWhere((p) => p.id == playlistId);
      if (index >= 0) {
        _playlists[index] = result.playlist;
      } else {
        _playlists.add(result.playlist);
      }
      _error = null;
    } catch (e) {
      _error = 'Could not load playlist: $e';
      debugPrint('PlaylistsService: loadTracks($playlistId) failed: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Create a playlist named [name], optionally seeded with [tracks].
  ///
  /// Returns the new playlist, or null if the server refused. The list is
  /// re-read rather than patched locally: `createPlaylist`'s response body
  /// varies between servers, so the freshly listed playlist is the only
  /// trustworthy copy.
  ///
  /// Which one that is, is settled without trusting that body at all — the id
  /// it reports is used when present, but a server that returns nothing still
  /// created the playlist, so the fallback is whichever id is in the list now
  /// and was not before. Ambiguity (nothing new, or several) yields null
  /// rather than a guess: the playlist exists either way, and the caller's
  /// only use for the result is deciding whether to open it.
  Future<Playlist?> create(String name, {List<Track> tracks = const []}) async {
    final api = _api;
    if (api == null) return null;

    try {
      final before = {for (final p in _playlists) p.id};
      final created = await api.createPlaylist(
        name,
        songIds: [for (final t in tracks) t.id],
      );
      _error = null;
      await load();

      if (created != null) {
        final reported = byId(created.id);
        if (reported != null) return reported;
      }
      final fresh = [
        for (final p in _playlists)
          if (!before.contains(p.id)) p,
      ];
      return fresh.length == 1 ? fresh.single : null;
    } catch (e) {
      _error = 'Could not create playlist: $e';
      debugPrint('PlaylistsService: create failed: $e');
      notifyListeners();
      return null;
    }
  }

  /// Append [tracks] to [playlistId]. Adding is by song id, so this is safe
  /// even if the playlist changed elsewhere since it was last read.
  Future<bool> addTracks(String playlistId, List<Track> tracks) async {
    final api = _api;
    if (api == null || tracks.isEmpty) return false;

    try {
      await api.addToPlaylist(playlistId, [for (final t in tracks) t.id]);
      _error = null;
      // Re-read so the song count and any open detail view are correct.
      await loadTracks(playlistId, force: true);
      return true;
    } catch (e) {
      _error = 'Could not add to playlist: $e';
      debugPrint('PlaylistsService: addTracks failed: $e');
      notifyListeners();
      return false;
    }
  }

  /// Remove [trackId] from [playlistId], where the UI showed it at [index].
  ///
  /// Subsonic removes by *position*, so this re-reads the playlist first and
  /// then locates the track by id: [index] is only a hint, used to pick the
  /// right one when a playlist contains the same track twice. If the server's
  /// order changed since the screen was drawn, the id is what keeps this from
  /// deleting the wrong track.
  Future<bool> removeTrack(
    String playlistId,
    int index, {
    required String trackId,
  }) async {
    final api = _api;
    if (api == null) return false;

    try {
      // Fresh order, immediately before computing the position to delete.
      await loadTracks(playlistId, force: true);
      final tracks = _tracks[playlistId];
      if (tracks == null) return false;

      // Prefer the hinted index when it still holds the expected track (which
      // is what disambiguates duplicates); otherwise find it afresh.
      final position =
          index >= 0 && index < tracks.length && tracks[index].id == trackId
          ? index
          : tracks.indexWhere((t) => t.id == trackId);
      if (position < 0) {
        // Someone else already removed it — the desired state, so re-reading
        // is enough and this is not an error worth showing.
        return true;
      }

      await api.removeFromPlaylist(playlistId, [position]);
      _error = null;
      await loadTracks(playlistId, force: true);
      return true;
    } catch (e) {
      _error = 'Could not remove from playlist: $e';
      debugPrint('PlaylistsService: removeTrack failed: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> rename(String playlistId, String name) async {
    final api = _api;
    if (api == null) return false;

    try {
      await api.renamePlaylist(playlistId, name);
      _error = null;
      await load();
      return true;
    } catch (e) {
      _error = 'Could not rename playlist: $e';
      debugPrint('PlaylistsService: rename failed: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> delete(String playlistId) async {
    final api = _api;
    if (api == null) return false;

    try {
      await api.deletePlaylist(playlistId);
      _tracks.remove(playlistId);
      _fetchingTracks.remove(playlistId);
      _error = null;
      await load();
      return true;
    } catch (e) {
      _error = 'Could not delete playlist: $e';
      debugPrint('PlaylistsService: delete failed: $e');
      notifyListeners();
      return false;
    }
  }

  /// Drop the last error once a screen has shown it.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
