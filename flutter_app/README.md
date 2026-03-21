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
cd flutter_app
flutter pub get
```

### 2. Run the App

The default server URL is set at build time via `--dart-define`. Edit `dart_defines.env` to change it, then pass it on the command line:

```bash
flutter run --dart-define=DEFAULT_SERVER_URL=https://your-navidrome-server:4533
```

If omitted, the value in `dart_defines.env` is used as the fallback default.

### 3. Build for Production

**Android APK:**
```bash
flutter build apk --dart-define=DEFAULT_SERVER_URL=https://your-server:4533
```

**Windows:**
```bash
flutter build windows --dart-define=DEFAULT_SERVER_URL=https://your-server:4533
```

**Web:**
```bash
flutter build web --dart-define=DEFAULT_SERVER_URL=https://your-server:4533
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

## Authentication

The app uses Subsonic token auth:
- Each request includes `u=<username>&t=<md5(password+salt)>&s=<salt>&v=1.16.1&c=AnywherePlayer&f=json`
- Login verifies credentials by calling the Subsonic `ping` endpoint
- Username and password are stored in SharedPreferences
- No signup flow -- users are created via the Navidrome web UI

## Android TV

The app automatically detects Android TV and shows a TV-optimized UI with:
- D-Pad navigation with focus management
- Large UI elements for 10-foot viewing
- Remote control media button support
- Dark theme optimized for TV displays

The Android manifest includes `LEANBACK_LAUNCHER` for TV launcher integration.

## Troubleshooting

### App won't connect
- Verify the `DEFAULT_SERVER_URL` was passed via `--dart-define` at build time
- Check that the Navidrome server is reachable from the device

### Audio not playing
- Check device logs (`adb logcat` on Android, `flutter logs` for others)
- Verify the Navidrome user has streaming permissions

### Android TV: app not in launcher
- Ensure `tv_banner.png` exists at `android/app/src/main/res/drawable-xhdpi/`
- Verify AndroidManifest.xml has the `LEANBACK_LAUNCHER` intent filter

## License

MIT License
