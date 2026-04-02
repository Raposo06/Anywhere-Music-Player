# Anywhere Music Player

> **Self-hosted, cross-platform music streaming powered by Navidrome.**
> *Write Once (Flutter), Host Anywhere (Navidrome), Play Everywhere (TV, PC, Phone).*

A private music streaming app that connects to a [Navidrome](https://www.navidrome.org/) server via the Subsonic API. Built with Flutter for Android TV, Android phones, Windows, and Web.

## Architecture

```
Flutter App  -->  Navidrome Server (/rest/*)
                    - Subsonic API (authentication, browsing, streaming)
                    - Scans and indexes your music library
                    - Serves audio streams and cover art
```

The Flutter app communicates exclusively through the **Subsonic API**. Navidrome handles music scanning, metadata, user management, streaming, and cover art out of the box.

### Key Subsonic Endpoints Used

| Function          | Endpoint                                                      |
|-------------------|---------------------------------------------------------------|
| Auth check        | `GET /rest/ping`                                              |
| Browse folders    | `GET /rest/getMusicFolders`, `GET /rest/getMusicDirectory`    |
| Search            | `GET /rest/search3`                                           |
| Stream audio      | `GET /rest/stream?id=X`                                       |
| Cover art         | `GET /rest/getCoverArt?id=X`                                  |

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

## Features

- Folder-based music browsing (mirrors your server's filesystem structure)
- Browse all tracks alphabetically with local search
- Audio streaming with background playback
- Lock screen / notification media controls (Android)
- System media transport controls (Windows)
- Album cover art display
- Android TV support with D-Pad / remote control navigation
- Responsive UI for phones, tablets, desktops, and TVs

## Project Structure

```
anywhere_music_player/lib/
  models/
    track.dart                   # Track model (Subsonic fields)
    folder.dart                  # Folder model
    user.dart                    # User model
  screens/
    login_screen.dart            # Credentials login
    home_screen.dart             # Folder browsing
    folder_detail_screen.dart    # Folder contents
    all_tracks_screen.dart       # All tracks list with search
    player_screen.dart           # Now playing (mobile/desktop)
    main_screen.dart             # Main navigation shell
    tv_home_screen.dart          # Android TV track list
    tv_player_screen.dart        # Android TV full-screen player
  services/
    subsonic_api_service.dart    # Subsonic API client
    auth_service.dart            # Auth (Subsonic token auth)
    audio_player_service.dart    # Audio playback (just_audio + media_kit on Windows)
    audio_handler.dart           # audio_service background handler
    library_scanner.dart         # Full library scanner + folder tree builder
    windows_media_controls_service.dart  # Windows SMTC integration
  utils/
    platform_detector.dart       # Android TV detection
    responsive.dart              # Responsive layout helpers
  widgets/
    mini_player.dart             # Mini player bar
  main.dart                      # App entry point
```

## Key Dependencies

| Package                        | Purpose                                         |
|--------------------------------|-------------------------------------------------|
| `just_audio`                   | Cross-platform audio streaming                  |
| `just_audio_media_kit`         | Windows/Linux audio backend (replaces WMF)      |
| `media_kit_libs_windows_audio` | Native MPV audio libraries for Windows          |
| `audio_service`                | Background playback + media controls            |
| `provider`                     | State management                                |
| `crypto`                       | MD5 hashing for Subsonic auth tokens            |
| `shared_preferences`           | Local credential storage                        |
| `http`                         | HTTP client for Subsonic API calls              |
| `permission_handler`           | Android notification permission                 |
| `smtc_windows`                 | Windows system media transport controls (SMTC)  |
| `window_manager`               | Windows title bar and window management         |
| `flutter_dotenv`               | Runtime `.env` configuration                    |

## Authentication

The app uses Subsonic token authentication: for every request it generates a random salt and computes `token = MD5(password + salt)`. Credentials are stored locally in SharedPreferences. No signup flow — users are created via the Navidrome web UI.

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

## License

MIT License
