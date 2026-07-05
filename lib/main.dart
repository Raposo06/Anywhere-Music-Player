import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'services/auth_service.dart';
import 'services/audio_player_service.dart';
import 'services/audio_handler.dart';
import 'services/library_scanner.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/tv_home_screen.dart';
import 'utils/platform_detector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bound the Flutter image cache. Default is 1000 entries / 100 MB, which a
  // music library with thousands of covers can blow through during long
  // scrolls — leading to OOM kills on lower-RAM Android devices. We render
  // each cover at a server-sized URL (small thumbnails + a larger player
  // cover), so 50 MB / 300 entries comfortably holds the working set.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50 MB
  PaintingBinding.instance.imageCache.maximumSize = 300;

  // Initialize media_kit backend for just_audio on desktop (replaces
  // just_audio_windows which had WMF threading deadlocks on startup).
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Initialize window manager early — must happen right after Flutter binding
  // init, before runApp(), per window_manager docs.
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
  }

  await dotenv.load(fileName: '.env');

  // Initialize native platform detection (Android TV detection)
  await PlatformDetector.initialize();

  // Initialize audio service for Android/iOS background playback and
  // lock screen controls. Skip on Windows — SMTC handles media controls there.
  MusicAudioHandler? audioHandler;
  final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (!isDesktop) {
    try {
      audioHandler = await AudioService.init(
        builder: () => MusicAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.anywhere_music_player.audio',
          androidNotificationChannelName: 'Music Playback',
          androidNotificationChannelDescription: 'Controls for music playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
          androidNotificationClickStartsActivity: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidShowNotificationBadge: true,
        ),
      );
      debugPrint('Audio service initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('Audio service initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  runApp(MyApp(audioHandler: audioHandler));
}

// ── PS1 Classic theme: deep navy background with PlayStation button colours ───
ThemeData _retroTheme() {
  // PlayStation button colours
  const psBlue   = Color(0xFF003791); // primary
  const psRed    = Color(0xFFE8112D); // secondary / error
  const psYellow = Color(0xFFF7C000); // tertiary
  const psGreen  = Color(0xFF00973B); // accents

  // Navy background tones (inspired by the PS1 boot screen)
  const bgDeep    = Color(0xFF0A1628); // scaffold
  const bgSurface = Color(0xFF142040); // app bar, bottom nav, sheets
  const bgCard    = Color(0xFF1C2E55); // cards, list tiles
  const outline   = Color(0xFF2A3F6F); // borders, dividers

  const scheme = ColorScheme.dark(
    primary:            psBlue,
    onPrimary:          Colors.white,
    primaryContainer:   Color(0xFF001A5C),
    onPrimaryContainer: Colors.white,
    secondary:          psRed,
    onSecondary:        Colors.white,
    tertiary:           psYellow,
    onTertiary:         Colors.black,
    surface:            bgSurface,
    onSurface:          Colors.white,
    // ignore: deprecated_member_use
    background:         bgDeep,
    // ignore: deprecated_member_use
    onBackground:       Colors.white,
    error:              psRed,
    onError:            Colors.white,
    surfaceContainerHighest: bgCard,
    onSurfaceVariant:   Color(0xFFB8C8E8),
    outline:            outline,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bgDeep,

    appBarTheme: const AppBarTheme(
      backgroundColor: bgSurface,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    cardTheme: const CardThemeData(
      color: bgCard,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
    ),

    dividerTheme: const DividerThemeData(color: outline),

    listTileTheme: const ListTileThemeData(
      iconColor: Color(0xFFB8C8E8),
      textColor: Colors.white,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: psBlue,
        foregroundColor: Colors.white,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: psGreen),
    ),

    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: psBlue, width: 2),
      ),
      labelStyle: TextStyle(color: Color(0xFFB8C8E8)),
      hintStyle: TextStyle(color: Color(0xFF6080A8)),
      prefixIconColor: Color(0xFFB8C8E8),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: bgSurface,
      selectedItemColor: psYellow,
      unselectedItemColor: Color(0xFF6080A8),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bgSurface,
      indicatorColor: const Color(0xFF001A5C),
      iconTheme: WidgetStateProperty.all(
        const IconThemeData(color: Colors.white),
      ),
    ),

    snackBarTheme: const SnackBarThemeData(
      backgroundColor: bgCard,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

class MyApp extends StatelessWidget {
  final MusicAudioHandler? audioHandler;

  const MyApp({super.key, this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Auth Service (owns the SubsonicApiService after login)
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(),
        ),

        // Audio Player Service
        ChangeNotifierProvider<AudioPlayerService>(
          create: (_) => AudioPlayerService(audioHandler: audioHandler),
        ),

        // Library Scanner - depends on AuthService for the API connection.
        // Provided at the top level so it's accessible to all routes
        // (including Navigator.push routes like FolderDetailScreen).
        ChangeNotifierProxyProvider<AuthService, LibraryScanner>(
          create: (_) => LibraryScanner(null),
          update: (_, auth, previous) {
            // Always reflect the current api reference. After logout the
            // auth service disposes its api client, so we must drop our
            // hold on it; on re-login a brand-new api is created and the
            // scanner must rebind to it (otherwise we'd hit
            // "Client is already closed" on the next request).
            if (previous != null && identical(previous.api, auth.apiService)) {
              return previous;
            }
            return LibraryScanner(auth.apiService);
          },
        ),
      ],
      child: MaterialApp(
        title: 'Anywhere Music Player',
        debugShowCheckedModeBanner: false,
        theme: _retroTheme(),
        themeMode: ThemeMode.dark,
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _initialized = false;
  bool _screenSizeDetected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Initialize auth state from storage
      if (mounted) {
        await context.read<AuthService>().initialize();
      }
      if (mounted) setState(() => _initialized = true);
      // Request notification permission for lock screen controls (Android 13+)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        _requestNotificationPermission();
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      debugPrint('Notification permission: $status');
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    // Initialize platform detection with screen size (fallback heuristic).
    // Only needs to run once — this build method re-runs on every auth
    // state change, and the detection result never changes at runtime.
    if (!_screenSizeDetected) {
      _screenSizeDetected = true;
      final size = MediaQuery.of(context).size;
      PlatformDetector.initializeWithScreenSize(size.width, size.height);
    }

    // Show loading screen only during initial auth check (not during login)
    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show appropriate screen based on auth state and platform
    if (!authService.isAuthenticated) {
      return const LoginScreen();
    }

    return PlatformDetector.isAndroidTV
        ? const TvHomeScreen()
        : const MainScreen();
  }
}
