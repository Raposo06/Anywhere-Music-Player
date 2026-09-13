import 'package:anywhere_music_player/services/library_cache.dart';
import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import 'fake_gonic.dart';

export 'fake_gonic.dart' show browseSong;

/// A real [LibraryScanner] over a fake folder-native server that browses to
/// [songs], with an in-memory cache — so a screen test drives the actual
/// module rather than a subclass that overrides its getters. Run `scan()`
/// inside `tester.runAsync(...)` before pumping: the fake server answers
/// over a MockClient, whose futures testWidgets' fake-async zone does not
/// advance under a plain pump.
LibraryScanner scannerWithSongs(List<Map<String, dynamic>> songs) {
  return LibraryScanner(
    SubsonicApiService(
      serverUrl: 'https://gonic.example.com',
      username: 'alice',
      password: 'secret',
      httpClient: gonicBrowseClient(songs),
    ),
    cache: MemoryLibraryCache(),
  );
}
