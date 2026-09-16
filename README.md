# Anywhere Music Player

> **Self-hosted desktop music streaming powered by Gonic.**

A private music streaming app that connects to a [Gonic](https://github.com/sentriz/gonic) server via the Subsonic API. Built with Flutter for Windows and Linux.

Browsing follows your **actual folder tree**, not an artist/album index derived from tags — which is why the server is Gonic, whose browse-by-folder keeps that tree intact. Any Subsonic-compatible server that does the same should work; see [docs/decisions.md](docs/decisions.md).

## Downloads

Every asset below comes from the **[latest release](https://github.com/Raposo06/Anywhere-Music-Player/releases/latest)**, built and published automatically by CI.

| Platform | Asset | Install |
|---|---|---|
| Windows | `AnywhereMusicPlayer-<version>-setup.exe` | [Inno Setup](https://jrsoftware.org/isinfo.php) installer — run it, nothing else needed |
| Linux (Arch) | `AnywhereMusicPlayer-<version>-x86_64.pkg.tar.zst` | `sudo pacman -U <file>` — pulls `gtk3`, `mpv`, `libsecret` as dependencies |

`SHA256SUMS` is published alongside them if you want to verify a download.

> **Windows — SmartScreen.** The installer is not code-signed, so Defender shows
> *"unrecognised publisher"*. Expected, not a warning about the binary: choose
> **More info → Run anyway**. Signing is a deliberate non-purchase — see
> [docs/decisions.md](docs/decisions.md).
>
> **Linux — Arch only.** The package is the only Linux artifact. Other distros
> would need a build from source; media_kit links the *system* libmpv rather
> than bundling it, which is what makes a distro-agnostic binary awkward.
>
> **Desktop only.** The app targeted Android phone and TV until 2026-09-13;
> that code was removed, along with the unused iOS and macOS scaffolding. See
> [docs/decisions.md](docs/decisions.md).

### Releases

The **git tag is the version.** Pushing a `v*` tag builds Windows and Linux and publishes a GitHub Release:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

The tag — not `pubspec.yaml`, not `installer.iss` — is what the workflow feeds to `flutter build --build-name` and `ISCC /DMyAppVersion`, so the version can't drift between artifacts. The build number is the Actions run number, so it only ever increases.

Current release: **v1.0.0** (`pubspec.yaml` reads `1.0.0+2`; the two hardcoded values only apply to a hand-run local build, the tag is what ships). Setup and troubleshooting for the pipeline live in [docs/operations.md](docs/operations.md).

## Architecture

```
Flutter App  -->  Gonic Server (/rest/*)
                    - Subsonic API (authentication, browsing, streaming)
                    - Scans and indexes your music library
                    - Keeps the real folder tree intact
                    - Serves audio streams and cover art
```

The Flutter app communicates exclusively through the **Subsonic API**. The server handles music scanning, metadata, user management, streaming, and cover art out of the box.

### Key Endpoints Used

Everything goes through `SubsonicApiService`, which builds `$baseUrl/rest/<endpoint>`
and appends token auth. The library scan walks the server's real directory tree
rather than using the tag-based (artist/album) endpoints — see
[docs/decisions.md](docs/decisions.md) for why.

| Function | Endpoint |
|---|---|
| Auth check | `GET /rest/ping` |
| Music folders | `GET /rest/getMusicFolders` — the roots the walk starts from |
| Browse library | `GET /rest/getIndexes`, then `GET /rest/getMusicDirectory?id=X` recursively, 8 directories at a time |
| Search | `GET /rest/search3` |
| Stream audio | `GET /rest/stream?id=X&format=raw` |
| Cover art | `GET /rest/getCoverArt?id=X` |
| Favourites | `GET /rest/star`, `/rest/unstar`, `/rest/getStarred2` — songs only |
| Now playing | `GET /rest/scrobble?id=X&submission=false` — feeds the server's live panel, doesn't count as a play |
| Scrobble | `GET /rest/scrobble?id=X&submission=true&time=<ms>` — `time` is when the listen *began*, so a play submitted partway through a long track is still timed correctly |
| Playlists | `GET /rest/getPlaylists`, `/rest/getPlaylist`, `/rest/createPlaylist`, `/rest/updatePlaylist`, `/rest/deletePlaylist` |

## Prerequisites

- **Flutter SDK** (3.8.0+)
- A running **Gonic** instance with music indexed

## Quick Start

### 1. Deploy Gonic

```yaml
# docker-compose.yml
services:
  gonic:
    image: sentriz/gonic:latest
    ports:
      - "4747:80"
    environment:
      GONIC_SCAN_INTERVAL: 60          # minutes
      GONIC_SCAN_AT_START_ENABLED: "true"
      GONIC_PLAYLISTS_PATH: /playlists
    volumes:
      - ./data:/data
      - ./playlists:/playlists
      - /path/to/music:/music:ro
```

The first user is created on first visit to Gonic's own web UI and becomes admin.

Two layout rules Gonic enforces on the music path: every file in a folder must
belong to the same album, and one album must not span folders. Browsing gets
strange otherwise, and no client-side setting compensates.

### 2. Configure the Flutter App

```bash
cd anywhere_music_player
cp .env.example .env
```

Edit `.env`:

```env
API_BASE_URL=https://your-gonic-server.com
```

Then install dependencies and run:

```bash
flutter pub get
flutter run
```

### 3. Build for Production

**Windows:**
```bash
flutter build windows
```

**Linux:** install libmpv first (`sudo pacman -S mpv` on Arch, `sudo apt install libmpv-dev mpv` on Debian/Ubuntu) — media_kit links against the system library rather than bundling it. Then:
```bash
flutter build linux
```
Output: `build/linux/x64/release/bundle/anywhere_music_player`.

To wrap that bundle in an Arch package the way CI does:
```bash
cd packaging/arch && makepkg -p PKGBUILD.bin -f --nodeps
sudo pacman -U anywhere-music-player-*.pkg.tar.zst
```

## Features

**Library & playback**
- Folder-based browsing that mirrors your server's filesystem structure
- Play All / Shuffle over the whole library, from the Library header
- Streaming with background playback, seeking, and gapless-style advance
- Manual queue (add / remove / reorder), plus shuffle and repeat (off / all / one) — both persisted across restarts
- ReplayGain volume normalization, attenuate-only so clipping is impossible
- Album cover art, with prefetching for upcoming tracks

**Server-side, shared with anything else pointed at the same server**
- Playlists: create, rename, delete, add and remove tracks
- Favourites: star songs from any track row, the mini player or Now Playing, with a dedicated list
- Scrobbling: plays reported back past half the track or four minutes, so play counts and "recently played" reflect this app

**Platform integration**
- System Media Transport Controls + keep-awake while playing (Windows)
- MPRIS media keys via a hand-rolled D-Bus server (Linux)

**Desktop shell**
- App-drawn title bar, sidebar navigation, folder grid, docked mini player
- Full-window Now Playing with a permanent "Up Next" queue panel
- Keyboard shortcuts: space, arrow-key seek/volume, Ctrl+arrow skip, Ctrl+F to focus search, Alt+← / Escape to go back

**Reliability**
- On-disk library cache for instant cold start
- Automatic recovery from mid-stream connection drops

**Not yet:** playlists can't be reordered (Subsonic has no reorder parameter); the library cache is a single file per install, wiped on logout.

## Project Structure

One desktop shell over a set of services that never import a widget.
Abridged; the shape matters more than the full file list.

```
lib/
  models/
    track.dart  folder.dart  playlist.dart  user.dart  cover_art_ref.dart
  screens/
    login_screen.dart              # Credentials login
    desktop/
      desktop_shell.dart           # Sidebar shell + nested navigators
      shell_navigation.dart        # The two moves only the shell can make
      desktop_library_screen.dart  desktop_folder_screen.dart
      desktop_player_screen.dart   # Full-window Now Playing
      desktop_playlists_screen.dart  desktop_favourites_screen.dart
  services/
    subsonic_api_service.dart      # Subsonic API client
    auth_service.dart              # Subsonic token auth
    audio_player_service.dart      # Playback (just_audio + media_kit)
    playback_cursor.dart           # Sequencing: order, shuffle, repeat, queue.
                                   #   Pure Dart, no player or Flutter import
    playback_policy.dart           # Scrobble threshold, ReplayGain curve. Pure Dart
    stream_url_resolver.dart       # "What's the URL for this track"
    now_playing_presence.dart      # "Tell the OS this is playing" — one seam,
    windows_presence.dart          #   two adapters: SMTC + taskbar + wakelock,
    linux_presence.dart            #   and a hand-rolled MPRIS D-Bus server
    windows_wakelock.dart
    notices.dart                   # One-shot failure messages, shown by the shell
    library_scanner.dart           # Cache-first scan; holds the FolderTree
    folder_walk.dart  folder_tree.dart  library_browser.dart  library_cache.dart
    session_scoped.dart            # Base for the three services bound to a login
    playlists_service.dart  favourites_service.dart
    playback_reporter.dart         # Scrobbling
  theme/
    app_colors.dart  app_theme.dart
  utils/
    now_playing_folder.dart
  widgets/
    scrub_bar.dart  cover_art.dart  play_actions.dart  favourite_button.dart
    add_to_playlist.dart  add_songs_to_playlist.dart
    desktop/
      window_chrome.dart           # App-drawn title bar
      sidebar.dart  up_next_panel.dart  desktop_mini_player.dart
      desktop_shortcuts.dart  desktop_track_row.dart
  main.dart                        # Entry point; hides the native frame on desktop
```

The extracted seams — `PlaybackCursor`, `PlaybackPolicy`, `StreamUrlResolver`,
`NowPlayingPresence`, `LibraryBrowser` — each carry a no-op or in-memory test
default, which is why the suite runs with no real platform channel.

## Key Dependencies

| Package                        | Purpose                                         |
|--------------------------------|-------------------------------------------------|
| `just_audio`                   | Cross-platform audio streaming                  |
| `just_audio_media_kit`         | Windows/Linux audio backend (replaces WMF)      |
| `media_kit_libs_windows_audio` | Native MPV audio libraries for Windows          |
| `media_kit_libs_linux`         | Links MPV audio to the system's libmpv on Linux |
| `smtc_windows`                 | Windows system media transport controls (SMTC)  |
| `windows_taskbar`              | Windows taskbar thumbnail playback buttons      |
| `dbus`                         | Linux MPRIS media keys — the D-Bus interface is hand-rolled on top of this |
| `provider`                     | State management                                |
| `crypto`                       | MD5 hashing for Subsonic auth tokens            |
| `flutter_secure_storage`       | Encrypted local credential storage              |
| `shared_preferences`           | Legacy credential storage, migrated on launch   |
| `path_provider`                | The library cache directory                     |
| `cached_network_image`         | Cover art loading and caching                   |
| `flutter_cache_manager`        | Pre-warms cover art without decoding it into the image cache |
| `scrollable_positioned_list`   | "Follow the playing track" in track lists       |
| `http`                         | HTTP client for Subsonic API calls              |
| `window_manager`               | Desktop title bar and window management         |
| `flutter_dotenv`               | Runtime `.env` configuration                    |

## Authentication

The app uses Subsonic token authentication: for every request it generates a random salt and computes `token = MD5(password + salt)`. Credentials are stored locally in encrypted storage (`flutter_secure_storage`); older installs that still had them in SharedPreferences get migrated automatically on the next launch. No signup flow — users are created via the server's own web UI.

## Troubleshooting

### App won't connect
- Verify `.env` exists in `anywhere_music_player/` and contains a valid `API_BASE_URL`
- Check that the server is reachable from the device

### Audio not playing
- Check `flutter logs`
- Verify the server user exists and can stream

### Windows: build fails with MAX_PATH error
- Enable long path support (see build instructions above) and restart your terminal

### Linux: build fails to link, or audio doesn't play
- Install libmpv (see build instructions above) — media_kit needs the system library present, it isn't bundled the way the Windows build is

## License

MIT License
