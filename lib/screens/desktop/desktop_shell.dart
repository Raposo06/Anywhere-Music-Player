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
import 'desktop_all_tracks_screen.dart';
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
  /// unwinds it) survives a trip to All Tracks and back. All Tracks has
  /// nothing to drill into, so it is a plain screen.
  final _libraryNavigator = GlobalKey<NavigatorState>();

  /// Playlists drills down too (list → one playlist), so it gets its own
  /// navigator for the same reason: the trail survives a trip to another
  /// destination and back.
  final _playlistsNavigator = GlobalKey<NavigatorState>();

  /// Name of the top route in the library navigator — the folder you are
  /// looking at, or null at the library root. Kept by [_TopRouteObserver]
  /// rather than published by each screen, so the screens stay unaware of the
  /// window chrome.
  final _libraryRouteName = ValueNotifier<String?>(null);
  late final _routeObserver = _TopRouteObserver(_libraryRouteName);

  @override
  void initState() {
    super.initState();
    // The phone home screen kicks the first scan off in its own initState.
    // Doing it at the shell level means it still runs if the user lands on
    // All Tracks first.
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
    // Order matters: the observer defers its writes to the end of a frame, so
    // it has to be silenced before the notifier it writes to goes away.
    _routeObserver.detach();
    _libraryRouteName.dispose();
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

  /// Go up one folder in the library trail.
  ///
  /// Only the Library destination has anything to go back through — All Tracks
  /// and Favourites are flat — so this is a no-op elsewhere rather than doing
  /// something surprising.
  ///
  /// [NavigatorState.canPop] is checked explicitly instead of using
  /// `maybePop`: this navigator is nested, so popping its *first* route would
  /// leave the shell with an empty navigator rather than being harmlessly
  /// refused.
  void _goBack() {
    final navigator = _activeNavigator?.currentState;
    if (navigator != null && navigator.canPop()) navigator.pop();
  }

  /// The nested navigator behind the current destination, or null for the flat
  /// ones (All Tracks, Favourites) which have nothing to go back through.
  GlobalKey<NavigatorState>? get _activeNavigator => switch (_destination) {
    SidebarDestination.library => _libraryNavigator,
    SidebarDestination.playlists => _playlistsNavigator,
    SidebarDestination.allTracks || SidebarDestination.favourites => null,
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

  /// The context line in the title bar: the folder you're in, or the
  /// destination name, ahead of the app name.
  String _chromeLabel(String? libraryRoute) {
    final context_ = switch (_destination) {
      SidebarDestination.allTracks => 'All Tracks',
      SidebarDestination.favourites => 'Favourites',
      SidebarDestination.playlists => 'Playlists',
      SidebarDestination.library => libraryRoute,
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
              ValueListenableBuilder<String?>(
                valueListenable: _libraryRouteName,
                builder: (context, libraryRoute, _) =>
                    WindowChrome(label: _chromeLabel(libraryRoute)),
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
                          SidebarDestination.allTracks => 1,
                          SidebarDestination.favourites => 2,
                          SidebarDestination.playlists => 3,
                        },
                        children: [
                          Navigator(
                            key: _libraryNavigator,
                            observers: [_routeObserver],
                            onGenerateRoute: (settings) => MaterialPageRoute(
                              settings: settings,
                              builder: (_) => const DesktopLibraryScreen(),
                            ),
                          ),
                          const DesktopAllTracksScreen(),
                          const DesktopFavouritesScreen(),
                          Navigator(
                            key: _playlistsNavigator,
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
/// it observes.
///
/// Folder routes carry their title in `RouteSettings.name` (see
/// [DesktopFolderScreen.route]); the library root has none, which reads as
/// "no context" and leaves the chrome showing just the app name.
class _TopRouteObserver extends NavigatorObserver {
  final ValueNotifier<String?> name;
  bool _attached = true;

  _TopRouteObserver(this.name);

  /// Stop writing to [name] — call before disposing it.
  void detach() => _attached = false;

  // The notifier is read during a build (ValueListenableBuilder), and these
  // fire mid-navigation — deferring to the end of the frame avoids
  // "setState called during build".
  void _publish(Route<dynamic>? route) {
    if (!_attached) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_attached) return;
      final routeName = route?.settings.name;
      // The library root is generated with Flutter's default '/' name, which
      // is a placeholder rather than a context worth showing.
      name.value = (routeName == null || routeName == '/') ? null : routeName;
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
