import 'package:flutter/foundation.dart';

import 'subsonic_api_service.dart';

/// A module whose lifetime is one logged-in session.
///
/// Holds the [SubsonicApiService] the instance was built for, and nothing
/// else. That is the whole point of the type: `MyApp`'s `sessionScoped`
/// provider compares [api] against the live session's client by identity and
/// rebuilds the module when they differ. Logging out disposes the client, so
/// an instance that outlived its session answers every request with
/// "Client is already closed" — the bug this exists to make impossible.
///
/// [api] is null while logged out. The provider tree is built once, before
/// login, so every session-scoped module has to cope with that.
abstract class SessionScoped with ChangeNotifier {
  SessionScoped(this.api);

  /// The client this instance is bound to, or null while logged out. Public
  /// because the identity comparison against the live session is the rebind
  /// trigger, and it happens in the provider layer.
  final SubsonicApiService? api;
}

/// Load-a-collection-from-the-server state, shared by [PlaylistsService] and
/// [FavouritesService]: fetch once, hold it, and let a screen tell
/// "not fetched yet" apart from "fetched and empty".
///
/// Deliberately *not* mixed into [LibraryScanner]. Its scan is a different
/// shape — cache-first, two-phase, and with a soft refresh error distinct
/// from a fatal one — and forcing it in here would give it two error fields.
mixin LoadStatus on SessionScoped {
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  bool get isLoading => _loading;

  /// True once a load has succeeded — lets a view tell "nothing here" apart
  /// from "not fetched yet".
  bool get isLoaded => _loaded;

  String? get error => _error;

  /// The message a *mutation* failed with. [runLoad] owns this during a load;
  /// everything else sets it here and notifies for itself.
  @protected
  set error(String? message) => _error = message;

  /// Drop the last error once a screen has shown it.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Run [body] as *the* load for this module, owning the flags around it.
  ///
  /// Concurrent calls collapse into the first, [isLoaded] flips only on
  /// success (so a failed load doesn't read as an empty collection), and
  /// listeners are notified on both edges. [what] names the collection in the
  /// user-facing error: "Could not load $what: ...".
  @protected
  Future<void> runLoad(
    String what,
    Future<void> Function(SubsonicApiService api) body,
  ) async {
    final api = this.api;
    if (api == null || _loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await body(api);
      _loaded = true;
    } catch (e) {
      _error = 'Could not load $what: $e';
      debugPrint('$runtimeType: load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
