# Flutter + Navidrome Architecture Review

## Overall Assessment: Solid foundation, but with notable gaps in efficiency and robustness

The app has clean separation of concerns (API layer, state management, UI) and correctly implements the Subsonic API protocol for Navidrome communication. However, there are several issues across security, performance, and API efficiency that should be addressed.

---

## 1. SECURITY ISSUES

### Critical: Plaintext password storage (`auth_service.dart:81-83`)
Credentials including the raw password are stored in `SharedPreferences` as plaintext. On Android, SharedPreferences is an XML file readable on rooted devices. On web, it's `localStorage`, visible in DevTools.
- **Fix**: Use `flutter_secure_storage` which leverages Keychain (iOS), EncryptedSharedPreferences (Android), or platform keystores.

### Medium: Auth tokens baked into stream/cover URLs (`subsonic_api_service.dart:82-92`)
`buildStreamUrl()` and `buildCoverArtUrl()` embed the auth token directly in the URL string. These URLs are stored in `Track` objects, logged via `debugPrint` (`audio_player_service.dart:177`), and passed to `Image.network()` which may cache them. The token+salt pair is generated once per URL build, so the credential material is static in each Track's lifetime.
- **Risk**: URL strings containing credentials can leak through logs, image cache directories, and network inspection.

### Low: debugPrint leaks sensitive data (`subsonic_api_service.dart:127`)
`debugPrint('Subsonic ping: $uri')` prints the full URI including auth params (`t=`, `s=`, `u=`) to the debug console.

---

## 2. API COMMUNICATION EFFICIENCY

### No HTTP timeouts (`subsonic_api_service.dart`)
Every `http.get(uri)` call uses the default `http` client with no timeout. On a slow or unresponsive Navidrome server, the app will hang indefinitely.
- **Fix**: Use `http.Client()` with a timeout, or switch to `package:dio` which supports timeouts, interceptors, and retry natively.

### No request cancellation
When the user types quickly in the search bar (`home_screen.dart:214`, `onChanged: _handleSearch`), each keystroke fires a new `search3` API call. Previous in-flight requests are never cancelled, leading to race conditions where an older response can overwrite a newer one.
- **Fix**: Implement debouncing (e.g., 300ms delay) and cancel previous requests using `CancelableOperation` or Dio's `CancelToken`.

### Recursive directory fetching is sequential (`subsonic_api_service.dart:252-265`)
`getAllTracksInDirectory()` fetches subdirectories one by one in a loop (`for (final folder in contents.folders)`). For a folder with 20 subfolders, this means 20 sequential HTTP requests.
- **Fix**: Use `Future.wait()` to fetch subdirectories in parallel:
```dart
final subResults = await Future.wait(
  contents.folders.where((f) => f.id != null).map((f) => getAllTracksInDirectory(f.id!))
);
```

### No response caching
Every navigation to a folder triggers a fresh API call. Going back and re-entering the same folder makes the same request again. Cover art images use `Image.network()` with no explicit `cacheWidth`/`cacheHeight` or `CachedNetworkImage`.
- **Fix**: Add in-memory caching (e.g., LRU cache) for directory listings and folder indexes. Use `cached_network_image` for cover art.

### No retry logic
Any transient network failure (brief WiFi dropout, server hiccup) results in an error screen with a manual "Retry" button. There's no automatic retry with backoff.

---

## 3. STATE MANAGEMENT ISSUES

### Excessive `notifyListeners()` in AudioPlayerService
The `positionStream` listener (`audio_player_service.dart:74-76`) calls `notifyListeners()` on every position update (~every 200ms). Combined with `bufferedPositionStream` (`line 82-84`) and `durationStream` (`line 78-80`), this triggers 5+ rebuilds per second across all widgets that `watch` this provider. Every screen in the app watches `AudioPlayerService` for the mini-player FAB, meaning all of them rebuild constantly during playback.
- **Fix**: Use `StreamBuilder` in the player UI instead of `notifyListeners()` for high-frequency streams. Or use `Selector` / `context.select()` to only rebuild on relevant changes.

### Provider accessed via `context.read()` in `initState` (`home_screen.dart:40`, `folder_detail_screen.dart:37`)
The `_api` getter uses `context.read<AuthService>()` which is called during `initState` → `_loadData()`. While this works because of `addPostFrameCallback` timing in the auth wrapper, it's fragile. If the widget tree changes, this could fail.

---

## 4. FLUTTER BUILD QUALITY

### Good practices observed:
- Proper `mounted` checks before `setState()` after async operations
- Clean `dispose()` of controllers and focus nodes
- Material 3 theme with light/dark mode support
- Responsive layout system with breakpoints
- Proper `const` widget constructors
- Clean record types for API return values (`({List<Folder> folders, List<Track> tracks})`)

### Issues:

#### `context.watch()` inside `_buildTrackTile` (`folder_detail_screen.dart:255`, `home_screen.dart:363`)
`context.watch<AudioPlayerService>()` is called inside item builder methods. Since these are part of the same widget's `build()` method, this is technically fine, but it means the entire list rebuilds on every player state change (including position updates ~5x/sec). For a list of 100 tracks, this is wasteful.
- **Fix**: Extract track tiles into separate `StatelessWidget` subclasses that use `Selector` to only rebuild when `currentTrack.id` changes.

#### No pagination/lazy loading for large libraries
`getFolders()` and `getDirectoryContents()` load all items at once. A Navidrome server with thousands of artists will load them all into memory in a single response.
- **Fix**: Use Subsonic API pagination parameters (`offset`, `count`) with a paginated `ListView`.

#### Single `AudioSource` per track (`audio_player_service.dart:333-347`)
Each track change calls `setAudioSource()` + `play()` separately. `just_audio` supports `ConcatenatingAudioSource` for gapless playback across a playlist, which would also enable pre-buffering the next track.
- **Fix**: Use `ConcatenatingAudioSource` for playlists to enable gapless playback and reduce latency between tracks.

#### `_playFolder` uses `context` after async gap (`home_screen.dart:128-158`)
`ScaffoldMessenger.of(context)` is called after `await api.getAllTracksInDirectory()`. While there's a `mounted` check for `Navigator`, the `ScaffoldMessenger` calls at lines 148-155 don't have `mounted` guards.

---

## 5. NAVIDROME-SPECIFIC CONCERNS

- **API version** (`subsonic_api_service.dart:24`): Using `v=1.16.1` is fine — Navidrome supports this well.
- **Client identification** (`_clientName = 'AnywherePlayer'`): Correct practice for Navidrome to track API clients.
- **Auth method**: Token auth (`md5(password+salt)`) is the correct modern approach. The legacy plaintext password method is avoided.

### Missing Navidrome features the app could leverage:
- `scrobble` — report playback to Navidrome for play count tracking
- `star`/`unstar` — favorites support
- `getAlbumList2` — recently added, most played, random albums
- `getPlaylists`/`getPlaylist` — server-side playlist support
- `getLyrics` — lyrics display

### Artist metadata inconsistency (`audio_handler.dart:98`)
`updateTrackInfo` uses `track.folderPath` as the artist name for the notification, while the Track model has a dedicated `artist` field. This means the lock screen / notification will show the folder path instead of the actual artist name.

---

## 6. SUMMARY OF PRIORITIES

| Priority | Issue | Impact |
|----------|-------|--------|
| **P0** | Plaintext password in SharedPreferences | Security |
| **P0** | Excessive `notifyListeners()` causing constant rebuilds | Performance |
| **P1** | No HTTP timeouts | Reliability |
| **P1** | No search debouncing / request cancellation | UX + race conditions |
| **P1** | Sequential recursive directory fetching | Performance |
| **P2** | No response caching for directories/indexes | Network efficiency |
| **P2** | Single AudioSource instead of ConcatenatingAudioSource | UX (gapless playback) |
| **P2** | Artist shown as folderPath in notifications | Correctness |
| **P3** | No pagination for large libraries | Scalability |
| **P3** | Missing Navidrome features (scrobble, favorites, playlists) | Feature completeness |

---

The architecture is clean and well-organized for a project of this scope. The most impactful improvements would be fixing the credential storage, adding HTTP timeouts, reducing unnecessary widget rebuilds from the position stream, and parallelizing the recursive directory fetch.
