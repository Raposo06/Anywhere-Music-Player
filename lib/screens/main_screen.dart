import 'package:flutter/material.dart';
import '../utils/platform_detector.dart';
import '../widgets/mini_player.dart';
import 'all_tracks_screen.dart';
import 'desktop/desktop_shell.dart';
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeScreen(),
          AllTracksScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          BottomNavigationBar(
            currentIndex: _currentIndex,
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
            ],
          ),
        ],
      ),
    );
  }
}
