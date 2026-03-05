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

| Function          | Endpoint                  |
|-------------------|---------------------------|
| Auth check        | `GET /rest/ping`          |
| Browse folders    | `GET /rest/getMusicFolders`, `GET /rest/getMusicDirectory` |
| Search            | `GET /rest/search3`       |
| Stream audio      | `GET /rest/stream?id=X`   |
| Cover art         | `GET /rest/getCoverArt?id=X` |

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

### 2. Build the Flutter App

```bash
cd flutter_app
flutter pub get

# Run with your Navidrome server URL baked in:
flutter run --dart-define=SERVER_URL=https://your-navidrome-server:4533
```

### 3. Build for Production

**Android (phone + TV):**
```bash
flutter build apk --dart-define=SERVER_URL=https://your-server:4533
```

**Windows:**
```bash
flutter build windows --dart-define=SERVER_URL=https://your-server:4533
```

**Web:**
```bash
flutter build web --dart-define=SERVER_URL=https://your-server:4533
```

## Features

- Folder-based music browsing (mirrors Navidrome library structure)
- Full-text search across tracks, albums, and artists
- Audio streaming with background playback
- Lock screen / notification media controls (Android)
- System media transport controls (Windows)
- Album cover art display
- Android TV support with D-Pad / remote control navigation
- Responsive UI for phones, tablets, desktops, and TVs

## Project Structure

```
flutter_app/lib/
  config/
    app_config.dart              # Compile-time server URL
  models/
    track.dart                   # Track model (Subsonic fields)
    folder.dart                  # Folder model with Subsonic ID
    user.dart                    # User model
  screens/
    login_screen.dart            # Username + password login
    home_screen.dart             # Folder browsing
    folder_detail_screen.dart    # Folder contents
    all_tracks_screen.dart       # All tracks view
    player_screen.dart           # Now playing
    main_screen.dart             # Main navigation shell
    tv_home_screen.dart          # Android TV interface
  services/
    subsonic_api_service.dart    # Subsonic API client
    auth_service.dart            # Auth (Subsonic token auth)
    audio_player_service.dart    # Audio playback (just_audio)
    audio_handler.dart           # audio_service handler
    windows_media_controls_service.dart  # Windows SMTC
  utils/
    platform_detector.dart       # TV detection
    responsive.dart              # Responsive layout helpers
  widgets/
    tv_focus_wrapper.dart        # D-Pad focus management
    tv_player_controls.dart      # TV player overlay
  main.dart                      # App entry point

scripts/
  upload.py                      # Upload music to MinIO
  download.py                    # Download music from MinIO
  convert_vbr.py                 # VBR to CBR MP3 converter
```

## TV Controls

| Remote Button       | Action              |
|----------------------|---------------------|
| D-Pad Up/Down        | Scroll through list |
| Center / Select      | Play track          |
| Back                 | Navigate back       |
| Media Play/Pause     | Toggle playback     |
| Media Next/Previous  | Skip tracks         |

## Authentication

The app uses Subsonic token authentication: for every request, it generates a random salt and computes `token = MD5(password + salt)`. Credentials (username + password) are stored locally in SharedPreferences.

The server URL is set at build time via `--dart-define=SERVER_URL=...` and is not user-configurable at runtime.

## License

MIT License
