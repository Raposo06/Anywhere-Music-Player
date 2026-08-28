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
import 'services/android_presence.dart';
import 'services/linux_presence.dart';
import 'services/now_playing_presence.dart';
import 'services/stream_url_resolver.dart';
import 'services/windows_presence.dart';
import 'services/library_scanner.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/tv_home_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/desktop/window_chrome.dart';
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
  // init, before runApp(), per window_manager docs. Linux is included now
  // that the desktop shell draws its own title bar and needs the same
  // window controls Windows does.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    // The redesign replaces the OS frame with WindowChrome. Hiding it here —
    // before the first frame — avoids the native bar flashing on launch.
    // WindowsPresence still calls setTitle(): that drives the taskbar entry,
    // which the hidden frame doesn't affect.
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        minimumSize: Size(900, 600),
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  await dotenv.load(fileName: '.env');

  // Initialize native platform detection (Android TV detection)
  await PlatformDetector.initialize();

  // Mints stream/cover-art URLs on demand from the *current* authenticated
  // session (see StreamUrlResolver) — a stable reference that outlives any
  // one AuthService instance, so AudioPlayerService and the audio handler
  // (both constructed once, here, before login even happens) keep working
  // across logout/re-login. MyApp wires it to AuthService's changes.
  final resolver = RotatingStreamUrlResolver();

  // Initialize audio service for Android/iOS background playback and
  // lock screen controls. Skip on Windows — SMTC handles media controls there.
  MusicAudioHandler? audioHandler;
  final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (!isDesktop) {
    try {
      audioHandler = await AudioService.init(
        builder: () => MusicAudioHandler(resolver: resolver),
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

  // Which adapter tells the OS what's playing — see NowPlayingPresence.
  // Windows gets SMTC/taskbar/wakelock; mobile gets the audio_service
  // notification (only if it initialized above); Linux gets MPRIS (hardware
  // media keys go through it — see LinuxPresence); nothing else gets one.
  final NowPlayingPresence presence = (!kIsWeb && Platform.isWindows)
      ? WindowsPresence(resolver: resolver)
      : audioHandler != null
          ? AndroidPresence(audioHandler)
          : (!kIsWeb && Platform.isLinux)
              ? LinuxPresence(resolver: resolver)
              : const NoPresence();

  runApp(MyApp(presence: presence, resolver: resolver));
}

class MyApp extends StatelessWidget {
  final NowPlayingPresence presence;
  final StreamUrlResolver resolver;

  const MyApp({
    super.key,
    this.presence = const NoPresence(),
    this.resolver = const NoResolver(),
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Auth Service (owns the SubsonicApiService after login). If
        // [resolver] is the rotating kind (always true in production — see
        // main()), keep it pointed at whatever session is current, so
        // AudioPlayerService and the audio handler — both constructed once,
        // before login — always resolve against the live session.
        ChangeNotifierProvider<AuthService>(
          create: (_) {
            final auth = AuthService();
            final resolver = this.resolver;
            if (resolver is RotatingStreamUrlResolver) {
              resolver.updateFrom(auth.apiService);
              auth.addListener(() => resolver.updateFrom(auth.apiService));
            }
            return auth;
          },
        ),

        // Audio Player Service
        ChangeNotifierProvider<AudioPlayerService>(
          create: (_) => AudioPlayerService(presence: presence, resolver: resolver),
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
        theme: buildAppTheme(),
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
      // Wrapped, like the login screen below, because both render before the
      // desktop shell exists and the native window frame is already hidden.
      return const DesktopWindowFrame(
        child: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    // Show appropriate screen based on auth state and platform
    if (!authService.isAuthenticated) {
      return const DesktopWindowFrame(child: LoginScreen());
    }

    return PlatformDetector.isAndroidTV
        ? const TvHomeScreen()
        : const MainScreen();
  }
}
