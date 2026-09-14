/// The two moves only the shell can make, offered to everything inside it.
///
/// Now Playing covers the whole window from the *root* navigator, and the
/// Library's folder trail lives in a navigator nested inside the shell —
/// so a list screen cannot open the player by itself, and the player cannot
/// open a folder by itself. Both used to be protocols: an `InheritedWidget`
/// carrying one callback for the first, and the player popping a
/// `FolderRequest` for the shell to `await` for the second. Now they are two
/// verbs on one module the shell provides. A widget reads it with
/// `context.read<ShellNavigation>()`; a test hands in a recording one.
abstract class ShellNavigation {
  /// Bring Now Playing to the foreground. A second call while it is already
  /// open is a no-op, so a stray call from a list still mounted behind it
  /// cannot stack another copy.
  void openNowPlaying();

  /// Show [path] in the Library: switch to that destination and push the
  /// folder on its trail. Closes Now Playing first if it is open — the
  /// folder is what the user asked to see.
  void showFolder({required String path, required String name});
}
