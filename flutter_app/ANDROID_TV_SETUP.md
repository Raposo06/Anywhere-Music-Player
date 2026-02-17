# Android TV Setup Guide

This guide will help you complete the Android TV implementation for Anywhere Music Player.

## ✅ Completed Setup

The following Android TV components have been created:

1. **Android Project Configuration**
   - ✅ AndroidManifest.xml with LEANBACK_LAUNCHER support
   - ✅ build.gradle files configured
   - ✅ MainActivity.kt created
   - ✅ Gradle configuration files

2. **TV-Optimized UI**
   - ✅ `TvHomeScreen` - Main TV interface with folders and tracks
   - ✅ `TvPlayerControls` - Large player controls for remote
   - ✅ `PlatformDetector` - Utility to detect TV platform

3. **Features Implemented**
   - ✅ D-pad navigation support
   - ✅ Focus management for remote controls
   - ✅ Large touch targets (10-foot UI)
   - ✅ Dark theme optimized for TV
   - ✅ Keyboard event handling (SELECT button)

## 🔧 Required Steps to Complete

### 1. Create Android Platform Files

Run this command in your Flutter project directory (Windows):

```bash
flutter create --platforms android .
```

This will generate the complete Android project structure. Our custom files will be merged in.

### 2. Create TV Banner Image

**Required**: Create a 320x180 pixel PNG image for the TV launcher

**Location**: `android/app/src/main/res/drawable-xhdpi/tv_banner.png`

**Design Guidelines**:
- 320x180 pixels (exact)
- Dark background (#1a1a1a recommended)
- App name "Anywhere Music Player" in large white text
- Music icon or logo
- Keep text large (readable from 10 feet away)

**Quick Option**: Use Android Asset Studio
- Visit: https://romannurik.github.io/AndroidAssetStudio/
- Select "TV Banner" generator
- Upload your app icon
- Download and save as `tv_banner.png`

### 3. Update Main App to Support TV

Modify `lib/main.dart` to detect TV and show appropriate UI:

```dart
import 'package:flutter/material.dart';
import 'utils/platform_detector.dart';
import 'screens/home_screen.dart';  // Your existing mobile screen
import 'screens/tv_home_screen.dart';  // New TV screen

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anywhere Music Player',
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) {
          // Initialize platform detection
          final size = MediaQuery.of(context).size;
          PlatformDetector.initializeWithScreenSize(size.width, size.height);

          // Show TV UI if on Android TV, otherwise mobile UI
          return PlatformDetector.isAndroidTV
              ? const TvHomeScreen()
              : const HomeScreen();
        },
      ),
    );
  }
}
```

### 4. Add TV Player Controls to TV Screen

Modify `lib/screens/tv_home_screen.dart` to include player controls:

```dart
import '../widgets/tv_player_controls.dart';

// In TvHomeScreen's build method, wrap the body in a Stack:
@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    body: Stack(
      children: [
        SafeArea(
          child: Row(
            children: [
              // ... existing folder and track lists
            ],
          ),
        ),

        // Player controls overlay at bottom
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TvPlayerControls(),
        ),
      ],
    ),
  );
}
```

### 5. Test on Android TV Emulator

**Create Android TV Emulator:**

1. Open Android Studio
2. Tools > Device Manager
3. Create Device > TV > Choose "Android TV (1080p)"
4. Download system image (API 33 recommended)
5. Finish setup

**Run on TV Emulator:**

```bash
flutter devices  # Find TV emulator device ID
flutter run -d <tv-emulator-id>
```

**Test D-pad Navigation:**
- Use arrow keys to navigate between folders and tracks
- Use Enter/Return to select items
- Use Media keys (Play/Pause, Next, Previous) if available

### 6. Handle Remote Control Media Buttons

The app already supports media button events through `audio_service` package. The AndroidManifest.xml includes the necessary receiver configuration.

**Test Media Buttons:**
- Play/Pause button on remote
- Next/Previous track buttons
- Stop button

### 7. Optional: Improve TV Detection

For more accurate TV detection, create a platform channel:

**Create** `android/app/src/main/kotlin/com/anywhere/music_player/TvDetector.kt`:

```kotlin
package com.anywhere.music_player

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class TvDetector {
    companion object {
        private const val CHANNEL = "com.anywhere.music_player/tv_detector"

        fun register(flutterEngine: FlutterEngine, context: Context) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler { call, result ->
                    if (call.method == "isAndroidTV") {
                        val uiModeManager = context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        val isTV = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                        result.success(isTV)
                    } else {
                        result.notImplemented()
                    }
                }
        }
    }
}
```

**Update** `MainActivity.kt`:

```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    TvDetector.register(flutterEngine, this)
}
```

**Use in Flutter** (`platform_detector.dart`):

```dart
static const platform = MethodChannel('com.anywhere.music_player/tv_detector');

static Future<bool> get isAndroidTV async {
  try {
    return await platform.invokeMethod('isAndroidTV');
  } catch (e) {
    return false;
  }
}
```

## 📱 Building for Android TV

### Debug Build

```bash
flutter build apk --debug
```

### Release Build

```bash
flutter build apk --release
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

### Install on TV

```bash
adb connect <tv-ip-address>  # For physical TV
adb install build/app/outputs/flutter-apk/app-release.apk
```

## 🎨 UI Customization

### Adjust Grid Columns

In `tv_home_screen.dart`, modify the grid:

```dart
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 4,  // Increase for more columns
  childAspectRatio: 2.5,
  crossAxisSpacing: 16,
  mainAxisSpacing: 16,
),
```

### Change Colors

All TV colors are defined in the widgets:
- Background: `Color(0xFF0F0F0F)`
- Card background: `Color(0xFF1A1A1A)`
- Selected: `Color(0xFF2D5F9F)`

### Font Sizes

All text uses large sizes (18-32px) for TV readability. Adjust in the respective widgets.

## 🐛 Troubleshooting

### Issue: App doesn't appear in TV launcher

**Solution**: Make sure `tv_banner.png` exists and AndroidManifest.xml has `LEANBACK_LAUNCHER` intent filter.

### Issue: D-pad navigation not working

**Solution**: Check that widgets use `Focus` widget and handle `KeyDownEvent` properly.

### Issue: "Platform not supported" error

**Solution**: Run `flutter clean && flutter pub get` and rebuild.

### Issue: App crashes on TV

**Solution**: Check logs with `adb logcat` to see error details.

## 📚 Resources

- [Android TV Design Guidelines](https://developer.android.com/design/tv)
- [Flutter TV Support](https://docs.flutter.dev/platform-integration/android/install-android#configure-your-target-android-device)
- [Android TV Developer Guide](https://developer.android.com/training/tv/start)

## ✨ Next Steps

After basic TV support is working, consider adding:

1. **Voice Search** - Integrate with Android TV voice input
2. **Content Recommendations** - Use Android TV recommendation system
3. **Picture-in-Picture** - Continue playback in PiP mode
4. **Chromecast** - Cast to other TVs
5. **Android TV Home Screen Integration** - Show recently played in TV launcher

---

**Need Help?** Check the Flutter logs with `flutter run -v` or Android logs with `adb logcat`.
