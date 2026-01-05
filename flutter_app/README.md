# Anywhere Music Player - Flutter App

Cross-platform music streaming app for **Web** and **Android TV**, built with Flutter.

## Features

- 🎵 Stream music from your self-hosted MinIO storage
- 🔐 JWT-based authentication
- 📁 Folder-based music organization
- 🎨 Album cover art display
- 🔍 Search tracks and folders
- 📺 Android TV support with D-Pad navigation
- 🌐 Web browser support
- 🎛️ Audio playback controls (play, pause, next, previous)
- 📊 Progress tracking and seeking

## Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK (included with Flutter)
- A running backend instance (PostgreSQL + PostgREST + MinIO)

## Project Structure

```
flutter_app/
├── lib/
│   ├── models/
│   │   ├── track.dart         # Track data model
│   │   └── user.dart          # User and auth response models
│   ├── screens/
│   │   ├── login_screen.dart  # Login UI
│   │   ├── signup_screen.dart # Signup UI
│   │   ├── home_screen.dart   # Music library with folders
│   │   └── player_screen.dart # Audio player with cover art
│   ├── services/
│   │   ├── api_service.dart           # PostgREST HTTP client
│   │   ├── auth_service.dart          # Authentication & JWT storage
│   │   └── audio_player_service.dart  # Audio playback (just_audio)
│   ├── widgets/
│   │   └── tv_focus_wrapper.dart      # Android TV D-Pad support
│   └── main.dart              # App entry point
├── .env.example               # Environment config template
├── pubspec.yaml               # Dependencies
└── analysis_options.yaml      # Linting rules
```

## Setup Instructions

### 1. Install Flutter

Follow the official guide: https://docs.flutter.dev/get-started/install

Verify installation:
```bash
flutter doctor
```

### 2. Install Dependencies

```bash
cd flutter_app
flutter pub get
```

### 3. Generate Code (JSON Serialization)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This generates the `.g.dart` files for JSON serialization.

### 4. Configure Environment

Create a `.env` file from the template:

```bash
cp .env.example .env
```

Edit `.env` with your backend API URL:

```bash
API_BASE_URL=https://api.yourdomain.com
```

**Important:**
- For **Web**: Use your public API domain (e.g., `https://api.yourdomain.com`)
- For **Android TV**: Use your local network IP if testing locally (e.g., `http://192.168.1.100:3000`)

### 5. Run the App

#### Web (for testing on PC):
```bash
flutter run -d chrome
```

#### Android TV:
```bash
flutter run -d android
```

#### Build for Production:

**Web:**
```bash
flutter build web
# Output: build/web/
```

**Android APK:**
```bash
flutter build apk
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Android TV optimized:**
```bash
flutter build apk --target-platform android-arm64
```

## Configuration

### PostgREST CORS (for Web)

Your PostgREST API must allow CORS from your Flutter Web domain. In Traefik (Coolify), add a middleware:

```yaml
http:
  middlewares:
    cors-headers:
      headers:
        accessControlAllowOriginList:
          - "https://music.yourdomain.com"
        accessControlAllowHeaders:
          - "*"
        accessControlAllowMethods:
          - "GET"
          - "POST"
          - "OPTIONS"
```

### Android TV Manifest

The app includes Android TV support. To enable leanback launcher, add to `android/app/src/main/AndroidManifest.xml`:

```xml
<application>
    <uses-feature android:name="android.software.leanback" android:required="false" />
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />

    <activity android:name=".MainActivity"
              android:banner="@drawable/banner">
        <intent-filter>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
        </intent-filter>
    </activity>
</application>
```

Create a banner image at `android/app/src/main/res/drawable-xhdpi/banner.png` (320x180px).

## Usage Guide

### 1. Create an Account

- Launch the app
- Click "Create Account"
- Enter email, username, and password (min 8 chars)
- Sign up

### 2. Login

- Enter your email and password
- Click "Login"

### 3. Browse Music

- Music is organized by **folders** (matching your upload folder structure)
- Expand a folder to see tracks
- Click a track to play

### 4. Search

- Use the search bar to find tracks or folders
- Search works across both track titles and folder names

### 5. Playback Controls

- **Play/Pause**: Toggle playback
- **Next/Previous**: Navigate playlist
- **Seek**: Drag the progress slider
- **Mini Player**: Click the floating button to return to player

### 6. Android TV Navigation

- Use **D-Pad** to navigate between UI elements
- **Center/Select button** to activate buttons and play tracks
- **Back button** to navigate back

## Architecture

### State Management

- **Provider** pattern for state management
- Three main services:
  - `AuthService`: User authentication & JWT storage
  - `ApiService`: HTTP client for PostgREST
  - `AudioPlayerService`: Audio playback with just_audio

### Data Flow

```
1. User logs in → AuthService stores JWT in SharedPreferences
2. AuthService provides JWT to ApiService
3. ApiService makes authenticated requests to PostgREST
4. Track data flows to UI via Provider
5. User clicks track → AudioPlayerService streams from MinIO
```

### Audio Streaming

- Uses **just_audio** package for cross-platform audio
- Streams MP3 files directly from MinIO URLs
- Supports background playback
- Auto-advances to next track in playlist

## Development

### Code Generation

When you modify model files (track.dart, user.dart), regenerate code:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Hot Reload

Flutter supports hot reload during development:

```bash
flutter run
# Press 'r' to hot reload
# Press 'R' to hot restart
```

### Debugging

Enable debug mode in main.dart:

```dart
MaterialApp(
  debugShowCheckedModeBanner: true, // Shows debug banner
  ...
)
```

Check logs:
```bash
flutter logs
```

## Troubleshooting

### Issue: "API_BASE_URL not found"

**Solution:** Create a `.env` file with your API URL:
```bash
echo "API_BASE_URL=https://api.yourdomain.com" > .env
```

### Issue: "Network error" on login/signup

**Solutions:**
1. Check that your backend is running
2. Verify API_BASE_URL is correct
3. For Web: Ensure CORS is configured in PostgREST/Traefik
4. For Android TV: Use local network IP if testing locally

### Issue: Tracks not loading

**Solutions:**
1. Verify you're logged in
2. Check that tracks exist in database
3. Ensure JWT token is valid (7-day expiration)
4. Check API logs for errors

### Issue: Audio not playing

**Solutions:**
1. Verify MinIO URLs are publicly accessible
2. Check browser console (Web) or logcat (Android) for errors
3. Ensure MinIO bucket policy allows public read access for tracks

### Issue: Cover art not showing

**Solution:** MinIO bucket must allow public read for the `covers/` subfolder.

## Deployment

### Web Deployment

1. Build the app:
   ```bash
   flutter build web --release
   ```

2. Deploy `build/web/` to your web server (Nginx, Apache, Coolify, etc.)

3. Example Nginx config:
   ```nginx
   server {
       listen 80;
       server_name music.yourdomain.com;
       root /var/www/flutter_app/build/web;

       location / {
           try_files $uri $uri/ /index.html;
       }
   }
   ```

### Android TV Deployment

1. Build APK:
   ```bash
   flutter build apk --release
   ```

2. Transfer `build/app/outputs/flutter-apk/app-release.apk` to Android TV

3. Install via ADB:
   ```bash
   adb install app-release.apk
   ```

   Or sideload using apps like "Apps2Fire" or "Send Files to TV".

## Next Steps

- [ ] Add playlist functionality
- [ ] Add favorites/liked tracks
- [ ] Implement shuffle mode
- [ ] Add repeat modes (one, all)
- [ ] Implement queue management
- [ ] Add offline caching
- [ ] Add lyrics display
- [ ] Implement equalizer

## Learn More

- [Flutter Documentation](https://docs.flutter.dev/)
- [just_audio Package](https://pub.dev/packages/just_audio)
- [Provider State Management](https://pub.dev/packages/provider)
- [Android TV Development](https://developer.android.com/training/tv)

## License

MIT License
