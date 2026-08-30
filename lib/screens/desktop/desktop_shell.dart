import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/audio_player_service.dart';
import '../../services/auth_service.dart';
import '../../services/favourites_service.dart';
import '../../services/library_scanner.dart';
import '../../theme/app_colors.dart';
import '../../widgets/desktop/desktop_mini_player.dart';
import '../../widgets/desktop/desktop_shortcuts.dart';
import '../../widgets/favourites_error_listener.dart';
import '../../widgets/desktop/sidebar.dart';
import '../../widgets/desktop/window_chrome.dart';
import 'desktop_favourites_screen.dart';
import 'desktop_folder_screen.dart';
import 'desktop_playlists_screen.dart';
import 'desktop_library_screen.dart';
import 'desktop_player_screen.dart';

/// Shared page padding for the shell's content area, per the design
/// (28px vertical, 32px horizontal).
const contentPadding = EdgeInsets.symmetric(horizontal: 32, vertical: 28);

/// The desktop application frame: title bar on top, sidebar on the left,
/// content in the middle, mini player docked at the bottom.
///
/// Replaces the phone's bottom tab bar with the sidebar; the destinations
/// themselves are the same two the tab bar had. Now Playing deliberately does
/// *not* live inside this frame — it is pushed on the root navigator so it
/// covers the whole window, as the design shows.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  SidebarDestination _destination = SidebarDestination.library;

  /// Library keeps its own navigator so folder drill-down (and the back that
  /// unwinds it) survives a trip to another destination and back.
  final _libraryNavigator = GlobalKey<NavigatorState>();

  /// Playlists drills down too (list → one playlist), so it gets its own
  /// navigator for the same reason: the trail survives a trip to another
  /// destination and back.
  final _playlistsNavigator = GlobalKey<NavigatorState>();

  /// Name of the top route in the library navigator — the folder you are
  /// looking at, or null at the library root — and whether that navigator can
  /// currently pop. Kept by [_NavigatorTracker] rather than published by each
  /// screen, so the screens stay unaware of the window chrome. The chrome uses
  /// the name for its context label and the pop flag for whether to show a
  /// back chevron.
  final _libraryRouteName = ValueNotifier<String?>(null);
  final _libraryCanPop = ValueNotifier<bool>(false);
  late final _libraryRouteObserver = _NavigatorTracker(
    _libraryRouteName,
    _libraryCanPop,
  );

  /// Same as above, for the playlists navigator — the playlist you have open,
  /// or null at the list root.
  final _playlistsRouteName = ValueNotifier<String?>(null);
  final _playlistsCanPop = ValueNotifier<bool>(false);
  late final _playlistsRouteObserver = _NavigatorTracker(
    _playlistsRouteName,
    _playlistsCanPop,
  );

  @override
  void initState() {
    super.initState();
    // The phone home screen kicks the first scan off in its own initState.
    // Doing it at the shell level means it still runs no matter which
    // destination the user lands on first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LibraryScanner>().scan();
      // Loaded up front, not when the Favourites tab is first opened: every
      // track row asks whether it is starred, and an unloaded service answers
      // "no" — so the hearts elsewhere would be wrong until you visited it.
      context.read<FavouritesService>().load();
    });
  }

  @override
  void dispose() {
    // Order matters: each observer defers its writes to the end of a frame,
    // so both are silenced before any notifier they write to goes away.
    _libraryRouteObserver.detach();
    _playlistsRouteObserver.detach();
    _libraryRouteName.dispose();
    _libraryCanPop.dispose();
    _playlistsRouteName.dispose();
    _playlistsCanPop.dispose();
    super.dispose();
  }

  Future<void> _handleSignOut() async {
    // Read all three before the first await — these are stable Provider
    // singletons, so holding local references avoids a `mounted` guard after
    // the await.
    final player = context.read<AudioPlayerService>();
    final scanner = context.read<LibraryScanner>();
    final auth = context.read<AuthService>();
    await player.stop();
    await scanner.resetAndClearCache();
    await auth.logout();
  }

  void _select(SidebarDestination destination) {
    if (destination == _destination) {
      // Clicking the active destination returns it to its root — the only way
      // out of a deep folder trail without walking back up it.
      if (_activeNavigator case final navigator?) {
        navigator.currentState?.popUntil((route) => route.isFirst);
      } else if (destination == SidebarDestination.favourites) {
        // Nothing to unwind here, so re-clicking re-syncs instead — the list
        // can go stale if you starred something from another client.
        context.read<FavouritesService>().load();
      }
      return;
    }
    setState(() => _destination = destination);
  }

  /// Go up one level in the active destination's trail — a folder in Library,
  /// a playlist in Playlists.
  ///
  /// Favourites is flat and has nothing to go back through, so this is a
  /// no-op there rather than doing something surprising.
  ///
  /// [NavigatorState.canPop] is checked explicitly instead of using
  /// `maybePop`: these navigators are nested, so popping the *first* route
  /// would leave the shell with an empty one rather than being harmlessly
  /// refused.
  void _goBack() {
    final navigator = _activeNavigator?.currentState;
    if (navigator != null && navigator.canPop()) navigator.pop();
  }

  /// The nested navigator behind the current destination, or null for
  /// Favourites, which has nothing to go back through.
  GlobalKey<NavigatorState>? get _activeNavigator => switch (_destination) {
    SidebarDestination.library => _libraryNavigator,
    SidebarDestination.playlists => _playlistsNavigator,
    SidebarDestination.favourites => null,
  };

  /// Whether the chrome should show a back chevron: only when the active
  /// destination has actually drilled somewhere a pop would leave. Reads the
  /// tracked flags rather than calling `canPop()` directly, because this is
  /// read from `build()` and only a [ValueNotifier] triggers a rebuild when a
  /// nested navigator changes out from under it.
  bool get _canGoBack => switch (_destination) {
    SidebarDestination.library => _libraryCanPop.value,
    SidebarDestination.playlists => _playlistsCanPop.value,
    SidebarDestination.favourites => false,
  };

  /// True while Now Playing is on screen, so a second request — a queue jump,
  /// a stray call from a list still mounted behind it — doesn't stack another
  /// copy of it on the root navigator.
  bool _playerOpen = false;

  Future<void> _openPlayer() async {
    if (_playerOpen) return;
    _playerOpen = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    // The player covers the whole window and so lives outside this shell; it
    // hands back a folder to open when the user clicks the track's path.
    final request = await navigator.push<FolderRequest>(
      MaterialPageRoute(builder: (_) => const DesktopPlayerScreen()),
    );
    _playerOpen = false;
    if (request == null || !mounted) return;
    setState(() => _destination = SidebarDestination.library);
    _libraryNavigator.currentState?.push(
      DesktopFolderScreen.route(
        folderPath: request.path,
        folderName: request.name,
      ),
    );
  }

  /// The context line in the title bar: the folder or playlist you're in, or
  /// the destination name, ahead of the app name.
  String get _chromeLabel {
    final context_ = switch (_destination) {
      SidebarDestination.favourites => 'Favourites',
      SidebarDestination.playlists => _playlistsRouteName.value ?? 'Playlists',
      SidebarDestination.library => _libraryRouteName.value,
    };
    return context_ == null ? appDisplayName : '$context_ — $appDisplayName';
  }

  @override
  Widget build(BuildContext context) {
    return DesktopPlayerLauncher(
      open: _openPlayer,
      child: DesktopPlaybackShortcuts(
        onBack: _goBack,
        child: Scaffold(
          backgroundColor: AppColors.win,
          body: Column(
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([
                  _libraryRouteName,
                  _libraryCanPop,
                  _playlistsRouteName,
                  _playlistsCanPop,
                ]),
                builder: (context, _) => WindowChrome(
                  label: _chromeLabel,
                  onBack: _canGoBack ? _goBack : null,
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Sidebar(
                      selected: _destination,
                      onSelect: _select,
                      onSignOut: _handleSignOut,
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: switch (_destination) {
                          SidebarDestination.library => 0,
                          SidebarDestination.favourites => 1,
                          SidebarDestination.playlists => 2,
                        },
                        children: [
                          Navigator(
                            key: _libraryNavigator,
                            observers: [_libraryRouteObserver],
                            onGenerateRoute: (settings) => MaterialPageRoute(
                              settings: settings,
                              builder: (_) => const DesktopLibraryScreen(),
                            ),
                          ),
                          const DesktopFavouritesScreen(),
                          Navigator(
                            key: _playlistsNavigator,
                            observers: [_playlistsRouteObserver],
                            onGenerateRoute: (settings) => MaterialPageRoute(
                              settings: settings,
                              builder: (_) => const DesktopPlaylistsScreen(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              DesktopMiniPlayer(onOpenPlayer: _openPlayer),
              const FavouritesErrorListener(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hands everything under [DesktopShell] the shell's "open Now Playing"
/// action.
///
/// The list screens are what know a track was just picked, but they can't push
/// Now Playing themselves: it goes on the *root* navigator and hands a folder
/// back to the shell when closed (see [FolderRequest]), so the shell has to own
/// the push. This is the wire between the two.
class DesktopPlayerLauncher extends InheritedWidget {
  final VoidCallback open;

  const DesktopPlayerLauncher({
    super.key,
    required this.open,
    required super.child,
  });

  /// Opens Now Playing from anywhere under the shell. A no-op outside it, so a
  /// screen reused off-shell (or in a test) still works.
  static void openPlayer(BuildContext context) {
    context.getInheritedWidgetOfExactType<DesktopPlayerLauncher>()?.open();
  }

  @override
  bool updateShouldNotify(DesktopPlayerLauncher oldWidget) =>
      open != oldWidget.open;
}

/// Publishes the name of whatever route is currently on top of the navigator
/// it observes, and whether that navigator can currently pop.
///
/// Folder and playlist routes carry their title in `RouteSettings.name` (see
/// [DesktopFolderScreen.route], `DesktopPlaylistScreen.route`); each root has
/// none, which reads as "no context" and leaves the chrome showing just the
/// app name — and not coincidentally, "no context" and "cannot pop" land on
/// the same routes, since a root is exactly where both are true.
class _NavigatorTracker extends NavigatorObserver {
  final ValueNotifier<String?> name;
  final ValueNotifier<bool> canPop;
  bool _attached = true;

  _NavigatorTracker(this.name, this.canPop);

  /// Stop writing to [name] and [canPop] — call before disposing them.
  void detach() => _attached = false;

  // The notifiers are read during a build (AnimatedBuilder), and these fire
  // mid-navigation — deferring to the end of the frame avoids "setState
  // called during build".
  void _publish(Route<dynamic>? route) {
    if (!_attached) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_attached) return;
      final routeName = route?.settings.name;
      // The root is generated with Flutter's default '/' name, which is a
      // placeholder rather than a context worth showing.
      name.value = (routeName == null || routeName == '/') ? null : routeName;
      canPop.value = navigator?.canPop() ?? false;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _publish(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _publish(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _publish(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _publish(newRoute);
}
