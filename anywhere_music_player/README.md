# Anywhere Music Player - Flutter App

Cross-platform music streaming app built with Flutter, connecting to a Navidrome server via the Subsonic API.

## Supported Platforms

- Android (phone + TV)
- Windows
- Web

## Prerequisites

- Flutter SDK (3.8.0+)
- A running Navidrome server

## Setup

### 1. Install Dependencies

```bash
cd anywhere_music_player
flutter pub get
```

### 2. Configure the Server URL

Create a `.env` file in the project root:

```
API_BASE_URL=https://your-navidrome-server:4533
```

This file is loaded at runtime via `flutter_dotenv`. Do not commit it — it is listed in `.gitignore`.

### 3. Run the App

```bash
flutter run
```

### 4. Build for Production

**Android APK:**
```bash
flutter build apk
```

**Windows:**
```bash
flutter build windows
```

> **Windows note:** If the build fails with a MAX_PATH error, enable long path support in Windows:
> ```powershell
> reg add HKLM\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f
> ```
> Then restart your terminal and retry.

**Web:**
```bash
flutter build web
```

## Project Structure

```
lib/
  models/
    track.dart                   # Track data model (Subsonic fields)
    folder.dart                  # Folder model
    user.dart                    # User model
  screens/
    login_screen.dart            # Login (username + password)
    home_screen.dart             # Music library with folder browsing
    folder_detail_screen.dart    # Folder contents
    all_tracks_screen.dart       # All tracks list with search
    player_screen.dart           # Now playing screen with cover art
    main_screen.dart             # Navigation shell
    tv_home_screen.dart          # Android TV interface
  services/
    subsonic_api_service.dart    # Subsonic API client
    auth_service.dart            # Subsonic token authentication
    audio_player_service.dart    # Audio playback via just_audio
    audio_handler.dart           # audio_service background handler
    library_scanner.dart         # Full library scanner + folder tree builder
    windows_media_controls_service.dart  # Windows SMTC integration
  utils/
    platform_detector.dart       # Android TV detection
    responsive.dart              # Responsive layout utilities
  widgets/
    mini_player.dart             # Mini player bar
    tv_player_controls.dart      # TV player overlay controls
  main.dart                      # Entry point, provider setup
```

## Key Dependencies

| Package              | Purpose                                |
|----------------------|----------------------------------------|
| `just_audio`         | Cross-platform audio streaming         |
| `audio_service`      | Background playback + media controls   |
| `provider`           | State management                       |
| `crypto`             | MD5 hashing for Subsonic auth tokens   |
| `shared_preferences` | Local credential storage               |
| `http`               | HTTP client for Subsonic API calls     |
| `permission_handler` | Android notification permission        |
| `smtc_windows`       | Windows system media transport controls|
| `flutter_dotenv`     | Runtime `.env` configuration           |

## Authentication

The app uses Subsonic token auth:
- Each request includes `u=<username>&t=<md5(password+salt)>&s=<salt>&v=1.16.1&c=AnywherePlayer&f=json`
- Login verifies credentials by calling the Subsonic `ping` endpoint
- Username and password are stored in SharedPreferences
- No signup flow — users are created via the Navidrome web UI

## Android TV

The app automatically detects Android TV (via `UiModeManager`) and shows a TV-optimized UI.

### Remote control navigation

| Button | Action |
|--------|--------|
| D-pad up/down | Navigate within the folder list or track grid |
| D-pad right (from folder list) | Jump to track grid |
| D-pad left (from track grid) | Return to folder list |
| D-pad down (from last grid row) | Jump to player controls |
| D-pad up (from player controls) | Return to track grid |
| D-pad left/right (on player controls) | Move between Shuffle / Prev / Play / Next / Repeat |
| Select / Enter | Open folder, play track, or activate button |
| Back | Deselect folder (first press) → exit app (second press) |

### TV launcher

The Android manifest includes `LEANBACK_LAUNCHER` for TV launcher integration and a `tv_banner.png` app banner.

## Troubleshooting

### App won't connect
- Verify `.env` exists in the project root and contains a valid `API_BASE_URL`
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
