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

### 2. Configure the Flutter App

Copy the example environment file and set your Navidrome server URL:

```bash
cd anywhere_music_player
cp .env.example .env
```

Edit `.env`:

```env
API_BASE_URL=https://your-navidrome-server.com
```

| Variable        | Description                              |
|-----------------|------------------------------------------|
| `API_BASE_URL`  | Base URL of your Navidrome instance      |

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

**Web:**
```bash
flutter build web
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
    player_screen.dart           # Now playing
    main_screen.dart             # Main navigation shell
    tv_home_screen.dart          # Android TV interface
  services/
    subsonic_api_service.dart    # Subsonic API client
    auth_service.dart            # Auth (Subsonic token auth)
    audio_player_service.dart    # Audio playback (just_audio)
    audio_handler.dart           # audio_service handler
    library_scanner.dart         # Full library scanner + folder tree builder
    windows_media_controls_service.dart  # Windows SMTC
  utils/
    platform_detector.dart       # TV detection
    responsive.dart              # Responsive layout helpers
  widgets/
    mini_player.dart             # Mini player bar
    tv_player_controls.dart      # TV player overlay
  main.dart                      # App entry point
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

The app uses Subsonic token authentication: for every request, it generates a random salt and computes `token = MD5(password + salt)`. The server URL and credentials are stored locally in SharedPreferences.

## License

MIT License
