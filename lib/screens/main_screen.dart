import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/favourites_service.dart';
import '../utils/platform_detector.dart';
import '../widgets/favourites_error_listener.dart';
import '../widgets/mini_player.dart';
import 'all_tracks_screen.dart';
import 'desktop/desktop_shell.dart';
import 'favourites_screen.dart';
import 'home_screen.dart';

/// Picks the layout for the form factor.
///
/// Desktop gets the redesign's sidebar shell; phone keeps the bottom tab bar
/// below. (Android TV never reaches here — `AuthWrapper` routes it straight to
/// `TvHomeScreen`.) Both share the same theme and the same services; only the
/// navigation chrome differs.
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (PlatformDetector.isDesktop) return const DesktopShell();
    return const _PhoneScaffold();
  }
}

class _PhoneScaffold extends StatefulWidget {
  const _PhoneScaffold();

  @override
  State<_PhoneScaffold> createState() => _PhoneScaffoldState();
}

class _PhoneScaffoldState extends State<_PhoneScaffold> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Loaded up front, not when the Favourites tab is first opened: every
    // track tile asks whether it is starred, and an unloaded service answers
    // "no" — so the hearts on the other tabs would be wrong until you visited
    // it. The desktop shell does the same.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FavouritesService>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [HomeScreen(), AllTracksScreen(), FavouritesScreen()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Renders nothing; it is a listener that reports a failed
          // star/unstar. Sits here so it is mounted for every tab.
          const FavouritesErrorListener(),
          const MiniPlayer(),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            // Three destinations no longer fit the default shifting style on
            // a narrow phone — fixed keeps every label visible.
            type: BottomNavigationBarType.fixed,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.folder),
                label: 'Folders',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music),
                label: 'All Tracks',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.favorite),
                label: 'Favourites',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
