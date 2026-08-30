import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'subsonic_api_service.dart';

/// The user's starred songs, held server-side by Navidrome and mirrored here.
///
/// Shaped like [LibraryScanner]: constructed with the current
/// [SubsonicApiService] (null while logged out) and rebound by `MyApp`'s
/// proxy provider when the session changes, so it never outlives its session.
///
/// **Songs only.** Subsonic can star albums and artists too, but folders in
/// this app are virtual — their id is the library path, not a Subsonic album
/// id — so there is nothing to star for one. See docs/decisions.md.
class FavouritesService with ChangeNotifier {
  final SubsonicApiService? _api;

  FavouritesService(this._api);

  SubsonicApiService? get api => _api;

  /// Starred tracks, newest first. Empty until [load] completes — callers get
  /// "not a favourite" for everything before then, which is why the desktop
  /// shell loads this at startup rather than when the Favourites tab is first
  /// opened.
  final List<Track> _starred = [];

  /// Mirrors [_starred] for O(1) lookups from track rows, which ask on every
  /// build. Kept in step with it by [_add] / [_remove] — never written
  /// directly.
  final Set<String> _starredIds = {};

  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<Track> get starred => List.unmodifiable(_starred);
  bool get isLoading => _loading;

  /// True once a load has succeeded — lets a view tell "no favourites yet"
  /// apart from "not fetched yet".
  bool get isLoaded => _loaded;
  String? get error => _error;

  bool isStarred(String trackId) => _starredIds.contains(trackId);

  void _add(Track track, {int at = 0}) {
    if (_starredIds.add(track.id)) _starred.insert(at, track);
  }

  void _remove(String trackId) {
    if (_starredIds.remove(trackId)) {
      _starred.removeWhere((t) => t.id == trackId);
    }
  }

  /// Fetch the starred list from the server, replacing what's held here.
  ///
  /// Safe to call repeatedly; concurrent calls collapse into the first.
  Future<void> load() async {
    final api = _api;
    if (api == null || _loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final songs = await api.getStarredSongs();
      _starred
        ..clear()
        ..addAll(songs);
      _starredIds
        ..clear()
        ..addAll(songs.map((t) => t.id));
      _loaded = true;
    } catch (e) {
      _error = 'Could not load favourites: $e';
      debugPrint('FavouritesService: load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Star or unstar [track], whichever it isn't already.
  ///
  /// Applied locally first and rolled back if the server rejects it: a heart
  /// that waits for a round trip before filling in feels broken, and the
  /// failure case is rare. [error] carries the reason when a rollback happens,
  /// so a screen can surface it.
  Future<void> toggle(Track track) async {
    final api = _api;
    if (api == null) return;

    final wasStarred = isStarred(track.id);
    // Captured so a rollback puts the track back where it was, rather than
    // promoting it to the top of the list.
    final previousIndex = _starred.indexWhere((t) => t.id == track.id);

    if (wasStarred) {
      _remove(track.id);
    } else {
      _add(track);
    }
    _error = null;
    notifyListeners();

    try {
      if (wasStarred) {
        await api.unstar(track.id);
      } else {
        await api.star(track.id);
      }
    } catch (e) {
      if (wasStarred) {
        _add(track, at: previousIndex < 0 ? 0 : previousIndex);
      } else {
        _remove(track.id);
      }
      _error = wasStarred
          ? 'Could not remove from favourites: $e'
          : 'Could not add to favourites: $e';
      debugPrint('FavouritesService: toggle failed for ${track.id}: $e');
      notifyListeners();
    }
  }

  /// Drop the last error once a screen has shown it.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
