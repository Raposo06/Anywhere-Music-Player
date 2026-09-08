import 'package:anywhere_music_player/services/library_scanner.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';
import 'fake_gonic.dart';

export 'fake_gonic.dart' show browseSong;

/// A [LibraryScanner] wired to a fake folder-native server that browses to
/// [songs] — see LibraryScanner.scan()/SubsonicApiService.getAllTracksByFolder().
/// Call `scan()` wrapped in `tester.runAsync(...)` before pumping the widget
/// (or, for scans a widget's own initState triggers, pump once then wrap the
/// wait in `tester.runAsync`) — scan() spawns a real isolate via compute(),
/// which testWidgets()'s fake-async zone never resolves under plain
/// pump/pumpAndSettle. See test/support/pump_helpers.dart's `waitForAsyncWork`.
LibraryScanner scannerWithSongs(List<Map<String, dynamic>> songs) {
  return LibraryScanner(
    SubsonicApiService(
      serverUrl: 'https://gonic.example.com',
      username: 'alice',
      password: 'secret',
      httpClient: gonicBrowseClient(songs),
    ),
  );
}
