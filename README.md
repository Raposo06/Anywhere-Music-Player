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

### 1b. (Optional) Sync music from MinIO

If your music library lives in a **MinIO bucket**, you can run a sidecar container using the official MinIO Client (`mc`) with `mc mirror --watch` to continuously sync files into Navidrome's music volume. The moment an MP3 is uploaded to MinIO, it is mirrored to the local folder and Navidrome picks it up on its next scan.

```yaml
# docker-compose.yml (add alongside navidrome service)
services:
  navidrome:
    image: deluan/navidrome:latest
    ports:
      - "4533:4533"
    environment:
      ND_SCANSCHEDULE: 5m          # Lower scan interval so new files appear faster
      ND_LOGLEVEL: info
    volumes:
      - ./data:/data
      - music:/music:ro            # Read-only for Navidrome

  minio-sync:
    image: minio/mc
    entrypoint: /bin/sh
    command: >
      -c "mc alias set myminio http://minio:9000 $${MINIO_ACCESS_KEY} $${MINIO_SECRET_KEY} &&
          mc mirror --watch --overwrite myminio/music-bucket /music"
    environment:
      MINIO_ACCESS_KEY: your-access-key
      MINIO_SECRET_KEY: your-secret-key
    volumes:
      - music:/music               # Shared with Navidrome
    restart: always

volumes:
  music:
```

**How it works:**
- `mc mirror --watch` subscribes to MinIO bucket events natively — no polling
- On `ObjectCreated`, the file is downloaded to `/music` in under a second
- On `ObjectRemoved`, the file is deleted from the mirror
- `restart: always` ensures the sync resumes automatically after a crash (it does a full diff on restart before resuming watch, so no files are missed)

> **Note:** Music is stored in both MinIO and the local volume, so plan for doubled disk usage.

### 2. Build the Flutter App

```bash
cd flutter_app
flutter pub get
flutter run
```

The server URL is entered on the login screen at runtime — no build-time configuration needed.

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
  models/
    track.dart                   # Track model (Subsonic fields)
    folder.dart                  # Folder model with Subsonic ID
    user.dart                    # User model
  screens/
    login_screen.dart            # Server URL + credentials login
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

The app uses Subsonic token authentication: for every request, it generates a random salt and computes `token = MD5(password + salt)`. The server URL and credentials are stored locally in SharedPreferences.

## License

MIT License
