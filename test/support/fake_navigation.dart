import 'package:anywhere_music_player/screens/desktop/shell_navigation.dart';

/// Records the shell moves a widget asks for, instead of pushing anything —
/// so a list-screen test can assert "tapping a row opened Now Playing" and
/// a player-screen test "clicking the folder line asked for that folder",
/// with no root navigator and no shell.
class RecordingShellNavigation implements ShellNavigation {
  int nowPlayingOpened = 0;
  final List<({String path, String name})> foldersShown = [];

  @override
  void openNowPlaying() => nowPlayingOpened++;

  @override
  void showFolder({required String path, required String name}) =>
      foldersShown.add((path: path, name: name));
}
