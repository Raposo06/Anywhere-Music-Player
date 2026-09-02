# Anywhere Music Player

> **Self-hosted, cross-platform music streaming powered by Navidrome.**
> *Write Once (Flutter), Host Anywhere (Navidrome), Play Everywhere (TV, PC, Phone).*

A private music streaming app that connects to a [Navidrome](https://www.navidrome.org/) server via the Subsonic API. Built with Flutter for Android TV, Android phones, Windows and Linux.

## Downloads

Every asset below comes from the **[latest release](https://github.com/Raposo06/Anywhere-Music-Player/releases/latest)**, built and published automatically by CI.

| Platform | Asset | Install |
|---|---|---|
| Android (phone + TV) | `AnywhereMusicPlayer-<version>.apk` | One APK covers both. Enable *Install unknown apps* first |
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
> **iOS / macOS.** Scaffolded by Flutter, never distributed. iOS needs a paid
> Apple Developer account and a Mac to build, and has no download-page path
> regardless (App Store or TestFlight only). Out of scope until that changes.

### Releases

The **git tag is the version.** Pushing a `v*` tag builds all three platforms and publishes a GitHub Release:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

The tag — not `pubspec.yaml`, not `installer.iss` — is what the workflow feeds to `flutter build --build-name` and `ISCC /DMyAppVersion`, so the version can't drift between artifacts. Android's `versionCode` is the Actions run number, so it only ever increases.

Current release: **v1.0.0** (`pubspec.yaml` reads `1.0.0+2`; the two hardcoded values only apply to a hand-run local build, the tag is what ships). Setup and troubleshooting for the pipeline live in [docs/operations.md](docs/operations.md).

## Architecture

```
Flutter App  -->  Navidrome Server (/rest/*)
                    - Subsonic API (authentication, browsing, streaming)
                    - Scans and indexes your music library
                    - Serves audio streams and cover art
```

The Flutter app communicates exclusively through the **Subsonic API**. Navidrome handles music scanning, metadata, user management, streaming, and cover art out of the box.

### Key Endpoints Used

Everything goes through `SubsonicApiService`, which builds `$baseUrl/rest/<endpoint>`
and appends token auth. Two calls are the exception and use Navidrome's **native**
REST API with a JWT instead — see [docs/decisions.md](docs/decisions.md) for why
browsing doesn't use the Subsonic tag-based endpoints.

| Function | Endpoint |
|---|---|
| Auth check | `GET /rest/ping` |
| Log in (native) | `POST /auth/login` — returns the JWT below |
| Browse library (native) | `GET /api/song` — paged 500 at a time, `x-nd-authorization: Bearer <jwt>` |
| Search | `GET /rest/search3` |
| Stream audio | `GET /rest/stream?id=X&format=raw` |
| Cover art | `GET /rest/getCoverArt?id=X` |
| Favourites | `GET /rest/star`, `/rest/unstar`, `/rest/getStarred2` — songs only |
| Now playing | `GET /rest/scrobble?id=X&submission=false` — feeds the server's live panel, doesn't count as a play |
| Scrobble | `GET /rest/scrobble?id=X&submission=true&time=<ms>` — `time` is when the listen *began*, so a play submitted partway through a long track is still timed correctly |
| Playlists | `GET /rest/getPlaylists`, `/rest/getPlaylist`, `/rest/createPlaylist`, `/rest/updatePlaylist`, `/rest/deletePlaylist` |

## Prerequisites

- **Flutter SDK** (3.8.0+)
- A running **Navidrome** instance with music indexed

## Quick Start

### 1. Deploy Navidrome

```yaml
# docker-compose.yml
services:
  navidrome:
    image: deluan/navidrome:latest
    ports:
      - "4533:4533"
    environment:
      ND_SCANSCHEDULE: 1h
      ND_LOGLEVEL: info
    volumes:
      - ./data:/data
      - /path/to/music:/music:ro
```

The first user created via the Navidrome web UI becomes admin.

### 2. Configure the Flutter App

```bash
cd anywhere_music_player
cp .env.example .env
```

Edit `.env`:

```env
API_BASE_URL=https://your-navidrome-server.com
```

Then install dependencies and run:

```bash
flutter pub get
flutter run
```

### 3. Build for Production

**Android (phone + TV):**
```bash
flutter build apk
```

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
- All-tracks list with local search, reached from the top of Playlists
- Streaming with background playback, seeking, and gapless-style advance
- Manual queue (add / remove / reorder), plus shuffle and repeat (off / all / one) — both persisted across restarts
- ReplayGain volume normalization, attenuate-only so clipping is impossible
- Album cover art, with prefetching for upcoming tracks

**Server-side, shared with Navidrome's web UI**
- Playlists (desktop + phone): create, rename, delete, add and remove tracks
- Favourites: star songs from any track row, the mini player or Now Playing, with a dedicated list on both layouts
- Scrobbling: plays reported back past half the track or four minutes, so play counts and "recently played" reflect this app

**Platform integration**
- Lock screen / notification controls (Android)
- System Media Transport Controls + keep-awake while playing (Windows)
- MPRIS media keys via a hand-rolled D-Bus server (Linux)
- Android TV UI with D-pad navigation, auto-detected via `UiModeManager`

**Desktop (Windows/Linux)**
- App-drawn title bar, sidebar navigation, folder grid, docked mini player
- Full-window Now Playing with a permanent "Up Next" queue panel
- Keyboard shortcuts: space, arrow-key seek/volume, Ctrl+arrow skip, Ctrl+F to focus search, Alt+← / Escape to go back

**Reliability**
- On-disk library cache for instant cold start
- Android on-disk stream cache (seekable replay, 2 GB cap)
- Automatic recovery from mid-stream connection drops

**Not yet:** favourites and playlists are absent on Android TV; playlists can't be reordered (Subsonic has no reorder parameter); the library cache is a single file per install, wiped on logout.

## Project Structure

Three UI layouts over one set of shared services. `MainScreen` picks between phone
and desktop; `AuthWrapper` sends Android TV straight to `TvHomeScreen`. The
layouts are separate screens on purpose — see [docs/decisions.md](docs/decisions.md).

Abridged; the shape matters more than the full 60-odd files.

```
lib/
  models/
    track.dart  folder.dart  playlist.dart  user.dart  cover_art_ref.dart
  screens/
    login_screen.dart              # Credentials login
    main_screen.dart               # Phone scaffold + layout switch
    home_screen.dart               # Folder browsing
    folder_detail_screen.dart      # Folder contents
    player_screen.dart             # Now playing (phone)
    playlists_screen.dart          # Playlists (phone)
    favourites_screen.dart         # Favourites (phone)
    tv_home_screen.dart            # Android TV track list
    tv_player_screen.dart          # Android TV full-screen player
    desktop/
      desktop_shell.dart           # Sidebar shell + nested navigators
      desktop_library_screen.dart  desktop_folder_screen.dart
      desktop_player_screen.dart   # Full-window Now Playing
      desktop_playlists_screen.dart  desktop_favourites_screen.dart
  services/
    subsonic_api_service.dart      # Subsonic API client
    auth_service.dart              # Subsonic token auth
    audio_player_service.dart      # Playback (just_audio + media_kit on desktop)
    audio_handler.dart             # audio_service background handler
    playback_cursor.dart           # Sequencing: order, shuffle, repeat, queue.
                                   #   Pure Dart, no player or Flutter import
    stream_url_resolver.dart       # "What's the URL for this track"
    stream_cache.dart              # Android on-disk cache vs direct streaming
    now_playing_presence.dart      # "Tell the OS this is playing" — one seam,
    android_presence.dart          #   three implementations
    windows_presence.dart
    linux_presence.dart
    mpris_service.dart             # Linux MPRIS D-Bus server
    windows_media_controls_service.dart   windows_wakelock.dart
    library_scanner.dart  library_cache.dart
    playlists_service.dart  favourites_service.dart
    playback_reporter.dart         # Scrobbling
  theme/
    app_colors.dart  app_theme.dart
  utils/
    platform_detector.dart         # Android TV detection
    responsive.dart  now_playing_folder.dart
  widgets/
    mini_player.dart  track_tile.dart  queue_sheet.dart  scrub_bar.dart
    cover_art.dart  play_actions.dart  favourite_button.dart
    add_to_playlist.dart  centred_message.dart
    desktop/
      window_chrome.dart           # App-drawn title bar
      sidebar.dart  up_next_panel.dart  desktop_mini_player.dart
      desktop_shortcuts.dart  desktop_track_row.dart
  main.dart                        # Entry point; hides the native frame on desktop
```

The four extracted seams — `PlaybackCursor`, `StreamUrlResolver`, `StreamCache`
and `NowPlayingPresence` — each carry a no-op or pass-through test default, which
is why the suite runs with no real Windows or Android platform channel.

## Key Dependencies

| Package                        | Purpose                                         |
|--------------------------------|-------------------------------------------------|
| `just_audio`                   | Cross-platform audio streaming                  |
| `just_audio_media_kit`         | Windows/Linux audio backend (replaces WMF)      |
| `media_kit_libs_windows_audio` | Native MPV audio libraries for Windows          |
| `media_kit_libs_linux`         | Links MPV audio to the system's libmpv on Linux |
| `audio_service`                | Background playback + media controls            |
| `smtc_windows`                 | Windows system media transport controls (SMTC)  |
| `windows_taskbar`              | Windows taskbar thumbnail playback buttons      |
| `dbus`                         | Linux MPRIS media keys — `audio_service` has no Linux implementation, so the D-Bus interface is hand-rolled on top of this |
| `provider`                     | State management                                |
| `crypto`                       | MD5 hashing for Subsonic auth tokens            |
| `flutter_secure_storage`       | Encrypted local credential storage              |
| `shared_preferences`           | Legacy credential storage, migrated on launch   |
| `path_provider`                | Cache directories (library + stream cache)      |
| `cached_network_image`         | Cover art loading and caching                   |
| `flutter_cache_manager`        | Pre-warms cover art without decoding it into the image cache |
| `scrollable_positioned_list`   | "Follow the playing track" in track lists       |
| `http`                         | HTTP client for Subsonic API calls              |
| `permission_handler`           | Android notification permission                 |
| `window_manager`               | Desktop title bar and window management         |
| `flutter_dotenv`               | Runtime `.env` configuration                    |

## Authentication

The app uses Subsonic token authentication: for every request it generates a random salt and computes `token = MD5(password + salt)`. Credentials are stored locally in encrypted storage (`flutter_secure_storage`); older installs that still had them in SharedPreferences get migrated automatically on the next launch. No signup flow — users are created via the Navidrome web UI.

## Android TV

The app automatically detects Android TV (via `UiModeManager`) and switches to a TV-optimized UI with large elements for 10-foot viewing.

### Screens

**Track list screen** — shows all tracks alphabetically with a "Shuffle All" button in the header.

**Full-screen player** — opens when a track starts playing. Shows large cover art, track title, progress bar, and playback controls. Press Back to return to the track list.

### Remote Control Navigation

**Track list screen**

| Button | Action |
|--------|--------|
| D-pad up/down | Move between tracks |
| D-pad down (from Shuffle All button) | Jump to first track |
| Select / Enter | Play selected track |
| Back | Exit app |

**Full-screen player**

| Button | Action |
|--------|--------|
| D-pad left/right | Move between Prev / Play-Pause / Next |
| Select / Enter | Activate focused button |
| Media Play/Pause | Toggle playback |
| Media Next/Previous | Skip tracks |
| Back | Return to track list |

The Android manifest includes `LEANBACK_LAUNCHER` for TV launcher integration.

## Troubleshooting

### App won't connect
- Verify `.env` exists in `anywhere_music_player/` and contains a valid `API_BASE_URL`
- Check that the Navidrome server is reachable from the device

### Audio not playing
- Check device logs (`adb logcat` on Android, `flutter logs` for others)
- Verify the Navidrome user has streaming permissions

### Android TV: app not in launcher
- Ensure `tv_banner.png` exists at `android/app/src/main/res/drawable/`
- Verify `AndroidManifest.xml` has the `LEANBACK_LAUNCHER` intent filter

### Windows: build fails with MAX_PATH error
- Enable long path support (see build instructions above) and restart your terminal

### Linux: build fails to link, or audio doesn't play
- Install libmpv (see build instructions above) — media_kit needs the system library present, it isn't bundled the way the Windows build is

## License

MIT License
